import Foundation
import Photos
import UIKit


/// 限制单次扫描的云端调用次数；max==0 表示禁用
actor CloudQuota {
    private var used = 0
    private let max: Int
    init(max: Int) { self.max = max }
    func take() -> Bool {
        if max <= 0 { return false }
        if used >= max { return false }
        used += 1
        return true
    }
    func count() -> Int { used }
}

@MainActor
final class ScanEngine: ObservableObject {
    @Published var progress = ScanProgress()
    @Published var isScanning = false
    @Published var groups: [CategoryGroup] = []
    @Published var errorMessage: String?
    @Published var lastDeletedCount: Int = 0
    @Published var skippedProtectedCount: Int = 0
    @Published var backgroundNote: String?
    @Published var cloudCallsUsed: Int = 0
    /// 扫完 0 命中时的可读原因
    @Published var emptyResultHint: String?

    private var scanTask: Task<Void, Never>?
    private let library = PhotoLibraryService.shared
    private let classifier = ImageClassifierService.shared
    private let settings = AppSettings.shared

    var minConfidence: Double {
        get { settings.minConfidence }
        set { settings.minConfidence = newValue }
    }

    /// 并行：默认偏高以提速（Vision 在子线程）
    var concurrency: Int = max(6, min(10, ProcessInfo.processInfo.activeProcessorCount + 2))

    var totalCandidates: Int {
        groups.reduce(0) { $0 + $1.items.count }
    }

    var selectedCount: Int {
        groups.reduce(0) { $0 + $1.selectedCount }
    }

    var selectedIds: [String] {
        groups.flatMap { $0.items.filter(\.isSelected).map(\.assetLocalId) }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        progress.phase = "已取消"
        BackgroundScanKeeper.shared.endBackgroundTask()
    }

    func startScan(
        preferScreenshots: Bool? = nil,
        includeRecentPhotos: Bool? = nil,
        limit: Int? = nil
    ) {
        cancel()
        isScanning = true
        errorMessage = nil
        backgroundNote = nil
        groups = []
        skippedProtectedCount = 0
        progress = ScanProgress(phase: "申请权限…", startedAt: Date())
        emptyResultHint = nil

        // 模式：设置里的 preciseMode
        classifier.preciseMode = settings.preciseMode
        classifier.useLocalML = settings.useLocalML

        BackgroundScanKeeper.shared.bind(engine: self)
        BackgroundScanKeeper.shared.beginBackgroundScanIfNeeded()
        BackgroundScanKeeper.shared.scheduleAppRefresh()

        let prefer = preferScreenshots ?? settings.preferScreenshots
        let includeRecent = includeRecentPhotos ?? settings.includeRecent
        let scanLimit = limit ?? settings.scanLimit
        let protectFav = settings.protectFavorites
        let albumIds = settings.protectedAlbumIds
        let conf = settings.minConfidence
        let workers = concurrency
        let precise = settings.preciseMode

        scanTask = Task { [weak self] in
            guard let self else { return }
            await self.performScan(
                prefer: prefer,
                includeRecent: includeRecent,
                scanLimit: scanLimit,
                protectFav: protectFav,
                albumIds: albumIds,
                conf: conf,
                workers: workers,
                precise: precise
            )
        }
    }

    private func performScan(
        prefer: Bool,
        includeRecent: Bool,
        scanLimit: Int,
        protectFav: Bool,
        albumIds: Set<String>,
        conf: Double,
        workers: Int,
        precise: Bool
    ) async {
        do {
            let status = try await library.ensureAuthorized()
            if status == .limited {
                errorMessage = PhotoAuthError.limitedHint.errorDescription
            }

            progress.phase = "读取相册…"
            let assets = library.fetchCandidateAssets(
                preferScreenshots: prefer,
                includeRecentPhotos: includeRecent,
                recentDays: self.settings.recentDays,
                scanAllPhotos: self.settings.scanAllPhotos,
                limit: scanLimit,
                skipFavorites: protectFav,
                protectedAlbumIds: albumIds
            )

            if assets.isEmpty {
                progress.phase = "未找到候选图片。请在设置打开「扫描全部」或提高上限/天数。"
                isScanning = false
                BackgroundScanKeeper.shared.endBackgroundTask()
                return
            }

            progress.total = assets.count
            progress.processed = 0
            progress.found = 0
            if progress.startedAt == nil { progress.startedAt = Date() }
            let scopeHint: String = {
                if self.settings.scanAllPhotos { return "全部图库" }
                var parts: [String] = []
                if prefer { parts.append("截图") }
                if includeRecent {
                    if self.settings.recentDays <= 0 { parts.append("全部日期") }
                    else { parts.append("近\(self.settings.recentDays)天") }
                }
                return parts.isEmpty ? "默认" : parts.joined(separator: "+")
            }()
            progress.phase = "\(precise ? "精准" : "快速") · \(scopeHint) · 候选 \(assets.count) 张"

            let cloudCfg = settings.cloudConfig()
            let quota = CloudQuota(max: cloudCfg.enabled ? max(0, cloudCfg.maxCallsPerScan) : 0)
            cloudCallsUsed = 0
            // 提示用户云端很慢，勿开「全部+精准+全量云」
            var foundItems: [JunkPhotoItem] = []
            foundItems.reserveCapacity(min(assets.count, 256))

            // 有云端时批次不必过大（云端本身限流 2）；本地阶段仍并行
            let batchSize = cloudCfg.enabled ? max(8, min(16, workers * 2)) : max(6, workers)
            var index = 0
            var lastUI = Date.distantPast

            while index < assets.count {
                if Task.isCancelled { break }
                BackgroundScanKeeper.shared.beginBackgroundScanIfNeeded()

                let end = min(index + batchSize, assets.count)
                let batch = Array(assets[index..<end])

                // —— 阶段 A：本地识别（并行，快）——
                struct LocalHit {
                    let asset: PHAsset
                    let isShot: Bool
                    let image: UIImage
                    var result: ClassificationResult
                }

                var locals: [LocalHit] = []
                locals.reserveCapacity(batch.count)

                await withTaskGroup(of: LocalHit?.self) { group in
                    for asset in batch {
                        group.addTask { [library, classifier] in
                            if protectFav && asset.isFavorite { return nil }
                            let isShot = asset.mediaSubtypes.contains(.photoScreenshot)
                            guard let image = await library.requestAnalysisImage(for: asset) else {
                                return nil
                            }
                            let result = await classifier.classify(image: image, isScreenshot: isShot)
                            return LocalHit(asset: asset, isShot: isShot, image: image, result: result)
                        }
                    }
                    for await hit in group {
                        if let hit { locals.append(hit) }
                    }
                }

                // —— 阶段 B：仅对「真不确定」走云端（默认不再对「正常照片」调 API）——
                if cloudCfg.enabled {
                    await withTaskGroup(of: (Int, ClassificationResult)?.self) { group in
                        for (i, hit) in locals.enumerated() {
                            let result = hit.result
                            let isShot = hit.isShot
                            let needCloud: Bool = {
                                // 关闭「仅不确定」时：仍限制为截图或已有本地弱命中，避免 4000 张全上云
                                if !cloudCfg.onlyUncertain {
                                    if let cat = result.category {
                                        return result.confidence < 0.8
                                    }
                                    return isShot
                                }
                                // 仅不确定：
                                if let cat = result.category {
                                    if result.confidence < cloudCfg.uncertainThreshold { return true }
                                    // 兜底类可复核
                                    if cat == .genericScreenshot || cat == .otherJunk { return true }
                                    // 本地高置信废图：信任本地，不上云
                                    return false
                                }
                                // 本地 none：绝大多数是正常照片 → 默认不上云
                                // 仅当「系统截图 + 有 OCR 文字」时才请云端二次看
                                if isShot && !result.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    return true
                                }
                                return false
                            }()

                            guard needCloud else { continue }
                            group.addTask {
                                guard await quota.take() else { return nil }
                                if let cloudResult = await VisionAPIService.shared.classify(
                                    image: hit.image,
                                    isScreenshot: isShot,
                                    ocrHint: result.ocrText,
                                    settings: cloudCfg
                                ) {
                                    return (i, cloudResult)
                                }
                                return nil
                            }
                        }
                        for await upd in group {
                            guard let (i, cloudResult) = upd else { continue }
                            var result = locals[i].result
                            if let cc = cloudResult.category {
                                if result.category == nil
                                    || cloudResult.confidence >= result.confidence - 0.05
                                    || (result.category == .genericScreenshot && cc != .genericScreenshot) {
                                    result = cloudResult
                                }
                            } else if result.category == .genericScreenshot || result.category == .otherJunk {
                                if cloudResult.confidence >= 0.55 {
                                    result = ClassificationResult(
                                        category: nil,
                                        confidence: cloudResult.confidence,
                                        reasons: cloudResult.reasons,
                                        hasQRCode: false,
                                        ocrText: result.ocrText
                                    )
                                }
                            }
                            locals[i].result = result
                        }
                    }
                }

                // —— 阶段 C：阈值过滤入结果 ——
                for hit in locals {
                    let result = hit.result
                    let asset = hit.asset
                    let isShot = hit.isShot
                    guard let category = result.category else { continue }
                    // 用户关闭的分类不收录
                    if !settings.isCategoryEnabled(category) { continue }

                    let need: Double
                    switch category {
                    case .takeout, .logistics, .qrCode, .payment, .verification:
                        need = min(conf, 0.35)
                    case .chatSnippet:
                        need = min(conf, 0.40)
                    case .otherJunk:
                        need = min(max(conf, 0.35), 0.45)
                    case .genericScreenshot:
                        // 系统截图兜底应能进结果（默认不勾选删除）
                        need = min(conf, 0.40)
                    }
                    guard result.confidence >= need else { continue }

                    foundItems.append(
                        JunkPhotoItem(
                            id: asset.localIdentifier,
                            assetLocalId: asset.localIdentifier,
                            category: category,
                            confidence: result.confidence,
                            reasons: result.reasons,
                            creationDate: asset.creationDate,
                            isScreenshot: isShot,
                            pixelWidth: asset.pixelWidth,
                            pixelHeight: asset.pixelHeight,
                            isSelected: category.defaultSelected
                        )
                    )
                }

                index = end
                let now = Date()
                // UI 刷新更稀：0.2s
                if now.timeIntervalSince(lastUI) > 0.15 || index >= assets.count {
                    lastUI = now
                    progress.processed = index
                    progress.found = foundItems.count
                    if let startAt = progress.startedAt {
                        let elapsed = max(0.001, now.timeIntervalSince(startAt))
                        let speed = Double(index) / elapsed
                        progress.itemsPerSecond = speed
                        let remain = assets.count - index
                        if speed > 0.05 && remain > 0 {
                            progress.etaSeconds = Double(remain) / speed
                        } else if remain == 0 {
                            progress.etaSeconds = 0
                        }
                    }
                    let used = await quota.count()
                    cloudCallsUsed = used
                    let cloudHint = settings.cloudVisionEnabled ? " · 云端\(used)" : ""
                    progress.phase = "\(precise ? "精准" : "快速") \(index)/\(assets.count) · 命中 \(foundItems.count)\(cloudHint)"
                    groups = Self.buildGroups(from: foundItems)
                }
            }

            if Task.isCancelled {
                progress.phase = "已取消"
                emptyResultHint = nil
            } else {
                groups = Self.buildGroups(from: foundItems)
                progress.processed = assets.count
                progress.found = foundItems.count
                progress.etaSeconds = 0
                let protectHint = protectFav || !albumIds.isEmpty ? " · 已跳过保护项" : ""
                progress.phase = "完成 · 共 \(foundItems.count) 张\(protectHint)"
                if foundItems.isEmpty {
                    emptyResultHint = Self.makeEmptyHint(
                        prefer: prefer,
                        includeRecent: includeRecent,
                        scanAll: settings.scanAllPhotos,
                        limit: scanLimit,
                        conf: conf,
                        enabledCount: settings.enabledCategoryIds.count
                    )
                } else {
                    emptyResultHint = nil
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            progress.phase = "出错"
        }

        isScanning = false
        BackgroundScanKeeper.shared.endBackgroundTask()
    }

    private static func makeEmptyHint(
        prefer: Bool,
        includeRecent: Bool,
        scanAll: Bool,
        limit: Int,
        conf: Double,
        enabledCount: Int
    ) -> String {
        var tips: [String] = ["没有命中可疑废图，可尝试："]
        if !scanAll && prefer && !includeRecent {
            tips.append("· 打开「包含普通照片」或「扫描全部照片」")
        }
        if !scanAll && includeRecent {
            tips.append("· 增大「普通照片天数」或打开「扫描全部」")
        }
        if limit > 0 && limit < 1000 {
            tips.append("· 提高「最多扫描」上限（当前 \(limit)）")
        }
        if conf > 0.4 {
            tips.append(String(format: "· 降低最低置信度（当前 %.0f%%）", conf * 100))
        }
        if enabledCount > 0 && enabledCount < JunkCategory.allCases.count {
            tips.append("· 检查设置里是否关闭了部分分类")
        }
        tips.append("· 确认照片权限为「所有照片」")
        tips.append("· 关闭「精准」用快速模式再扫一轮")
        return tips.joined(separator: "\n")
    }

    private static func buildGroups(from items: [JunkPhotoItem]) -> [CategoryGroup] {
        let dict = Dictionary(grouping: items, by: \.category)
        return JunkCategory.allCases.compactMap { cat in
            guard var list = dict[cat], !list.isEmpty else { return nil }
            list.sort {
                if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
                return ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
            }
            return CategoryGroup(category: cat, items: list)
        }
    }

    func setSelected(id: String, selected: Bool) {
        for g in groups.indices {
            if let i = groups[g].items.firstIndex(where: { $0.id == id }) {
                groups[g].items[i].isSelected = selected
                return
            }
        }
    }

    func setCategorySelected(_ category: JunkCategory, selected: Bool) {
        guard let gi = groups.firstIndex(where: { $0.category == category }) else { return }
        for i in groups[gi].items.indices {
            groups[gi].items[i].isSelected = selected
        }
    }

    func selectAll(_ selected: Bool) {
        for g in groups.indices {
            for i in groups[g].items.indices {
                groups[g].items[i].isSelected = selected
            }
        }
    }

    func deleteSelected() async -> Result<Int, Error> {
        let ids = selectedIds
        guard !ids.isEmpty else {
            return .failure(NSError(
                domain: "PhotoJunkCleaner",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "请先勾选要删除的图片"]
            ))
        }
        do {
            let n = try await library.deleteAssets(withLocalIds: ids)
            for g in groups.indices {
                groups[g].items.removeAll { ids.contains($0.assetLocalId) }
            }
            groups.removeAll { $0.items.isEmpty }
            lastDeletedCount = n
            return .success(n)
        } catch {
            return .failure(error)
        }
    }
}
