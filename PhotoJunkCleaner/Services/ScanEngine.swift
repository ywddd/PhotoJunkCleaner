import Foundation
import Photos
import UIKit

@MainActor
final class ScanEngine: ObservableObject {
    @Published var progress = ScanProgress()
    @Published var isScanning = false
    @Published var groups: [CategoryGroup] = []
    @Published var errorMessage: String?
    @Published var lastDeletedCount: Int = 0
    @Published var skippedProtectedCount: Int = 0

    private var scanTask: Task<Void, Never>?
    private let library = PhotoLibraryService.shared
    private let classifier = ImageClassifierService.shared
    private let settings = AppSettings.shared

    var minConfidence: Double {
        get { settings.minConfidence }
        set { settings.minConfidence = newValue }
    }

    var concurrency: Int = 3

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
    }

    func startScan(
        preferScreenshots: Bool? = nil,
        includeRecentPhotos: Bool? = nil,
        limit: Int? = nil
    ) {
        cancel()
        isScanning = true
        errorMessage = nil
        groups = []
        skippedProtectedCount = 0
        progress = ScanProgress(phase: "申请权限…")

        let prefer = preferScreenshots ?? settings.preferScreenshots
        let includeRecent = includeRecentPhotos ?? settings.includeRecent
        let scanLimit = limit ?? settings.scanLimit
        let protectFav = settings.protectFavorites
        let albumIds = settings.protectedAlbumIds
        let conf = settings.minConfidence

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let status = try await library.ensureAuthorized()
                if status == .limited {
                    self.errorMessage = PhotoAuthError.limitedHint.errorDescription
                }

                self.progress.phase = "读取相册…"
                let assets = library.fetchCandidateAssets(
                    preferScreenshots: prefer,
                    includeRecentPhotos: includeRecent,
                    limit: scanLimit,
                    skipFavorites: protectFav,
                    protectedAlbumIds: albumIds
                )

                if assets.isEmpty {
                    self.progress.phase = "未找到候选图片（可能全被白名单过滤）"
                    self.isScanning = false
                    return
                }

                self.progress.total = assets.count
                self.progress.processed = 0
                self.progress.found = 0
                self.progress.phase = "智能识别中…"

                var foundItems: [JunkPhotoItem] = []
                foundItems.reserveCapacity(min(assets.count, 256))

                let batchSize = max(1, concurrency)
                var index = 0
                while index < assets.count {
                    if Task.isCancelled { break }
                    let end = min(index + batchSize, assets.count)
                    let batch = Array(assets[index..<end])

                    await withTaskGroup(of: JunkPhotoItem?.self) { group in
                        for asset in batch {
                            group.addTask { [self] in
                                // 扫描期再挡一次收藏
                                if protectFav && asset.isFavorite { return nil }
                                let isShot = asset.mediaSubtypes.contains(.photoScreenshot)
                                guard let image = await self.library.requestAnalysisImage(for: asset) else {
                                    return nil
                                }
                                let result = await self.classifier.classify(image: image, isScreenshot: isShot)
                                guard let category = result.category,
                                      result.confidence >= conf else {
                                    return nil
                                }
                                return JunkPhotoItem(
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
                            }
                        }
                        for await item in group {
                            if let item {
                                foundItems.append(item)
                            }
                        }
                    }

                    index = end
                    self.progress.processed = index
                    self.progress.found = foundItems.count
                    self.progress.phase = "识别中 \(index)/\(assets.count) · 命中 \(foundItems.count)"
                    self.groups = Self.buildGroups(from: foundItems)
                }

                if Task.isCancelled {
                    self.progress.phase = "已取消"
                } else {
                    self.groups = Self.buildGroups(from: foundItems)
                    let protectHint = protectFav || !albumIds.isEmpty ? " · 已跳过保护项" : ""
                    self.progress.phase = "完成 · 共 \(foundItems.count) 张候选\(protectHint)"
                }
            } catch {
                self.errorMessage = error.localizedDescription
                self.progress.phase = "出错"
            }
            self.isScanning = false
        }
    }

    private static func buildGroups(from items: [JunkPhotoItem]) -> [CategoryGroup] {
        let dict = Dictionary(grouping: items, by: \.category)
        return JunkCategory.allCases.compactMap { cat in
            guard var list = dict[cat], !list.isEmpty else { return nil }
            list.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
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
