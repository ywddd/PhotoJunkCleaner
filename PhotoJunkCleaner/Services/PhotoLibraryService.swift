import Foundation
import Photos
import UIKit

enum PhotoAuthError: LocalizedError {
    case denied
    case restricted
    case limitedHint

    var errorDescription: String? {
        switch self {
        case .denied:
            return "没有相册权限。请到 设置 → 隐私与安全性 → 照片 中允许访问。"
        case .restricted:
            return "相册访问受系统限制。"
        case .limitedHint:
            return "当前为「有限访问」，建议选择「所有照片」以扫描完整相册。"
        }
    }
}

final class PhotoLibraryService {
    static let shared = PhotoLibraryService()
    private init() {}

    func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                cont.resume(returning: status)
            }
        }
    }

    func ensureAuthorized() async throws -> PHAuthorizationStatus {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await requestAuthorization()
        }
        switch status {
        case .authorized, .limited:
            return status
        case .notDetermined:
            // 理论上 request 后不应仍为 notDetermined
            throw PhotoAuthError.denied
        case .denied:
            throw PhotoAuthError.denied
        case .restricted:
            throw PhotoAuthError.restricted
        @unknown default:
            throw PhotoAuthError.denied
        }
    }

    /// 列出用户相册 + 智能相册（供白名单选择）
    func listAlbums() -> [AlbumInfo] {
        var list: [AlbumInfo] = []

        let userOpts = PHFetchOptions()
        userOpts.sortDescriptors = [NSSortDescriptor(key: "localizedTitle", ascending: true)]
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: userOpts
        )
        userAlbums.enumerateObjects { col, _, _ in
            let count = PHAsset.fetchAssets(in: col, options: nil).count
            guard count > 0 else { return }
            list.append(AlbumInfo(
                id: col.localIdentifier,
                title: col.localizedTitle ?? "未命名相册",
                count: count,
                isUserAlbum: true
            ))
        }

        let smart = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .any,
            options: nil
        )
        smart.enumerateObjects { col, _, _ in
            // 只暴露常见智能相册，避免过多噪音
            let allowed: Set<PHAssetCollectionSubtype> = [
                .smartAlbumFavorites,
                .smartAlbumUserLibrary,
                .smartAlbumScreenshots,
                .smartAlbumSelfPortraits,
                .smartAlbumPanoramas,
                .smartAlbumLivePhotos,
                .smartAlbumRecentlyAdded
            ]
            guard allowed.contains(col.assetCollectionSubtype) else { return }
            let count = PHAsset.fetchAssets(in: col, options: nil).count
            guard count > 0 else { return }
            list.append(AlbumInfo(
                id: col.localIdentifier,
                title: col.localizedTitle ?? "智能相册",
                count: count,
                isUserAlbum: false
            ))
        }

        return list
    }

    /// 白名单相册内的所有 asset id
    func assetIds(inAlbumIds albumIds: Set<String>) -> Set<String> {
        guard !albumIds.isEmpty else { return [] }
        var ids = Set<String>()
        for albumId in albumIds {
            let cols = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumId],
                options: nil
            )
            cols.enumerateObjects { col, _, _ in
                let assets = PHAsset.fetchAssets(in: col, options: nil)
                assets.enumerateObjects { asset, _, _ in
                    ids.insert(asset.localIdentifier)
                }
            }
        }
        return ids
    }

    /// 优先截图，可附带最近普通照片；可跳过收藏与白名单相册
    func fetchCandidateAssets(
        preferScreenshots: Bool = true,
        includeRecentPhotos: Bool = false,
        recentDays: Int = 90,
        limit: Int = 2000,
        skipFavorites: Bool = true,
        protectedAlbumIds: Set<String> = []
    ) -> [PHAsset] {
        var results: [PHAsset] = []
        var seen = Set<String>()
        let protectedAssets = assetIds(inAlbumIds: protectedAlbumIds)

        func consider(_ asset: PHAsset) {
            if skipFavorites && asset.isFavorite { return }
            if protectedAssets.contains(asset.localIdentifier) { return }
            if seen.insert(asset.localIdentifier).inserted {
                results.append(asset)
            }
        }

        if preferScreenshots {
            let opts = PHFetchOptions()
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            opts.predicate = NSPredicate(
                format: "(mediaSubtype & %d) != 0",
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
            opts.fetchLimit = limit * 2 // 过滤后可能变少，多取一些
            let shots = PHAsset.fetchAssets(with: .image, options: opts)
            shots.enumerateObjects { asset, _, stop in
                if results.count >= limit {
                    stop.pointee = true
                    return
                }
                consider(asset)
            }
        }

        if includeRecentPhotos {
            let opts = PHFetchOptions()
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            if let start = Calendar.current.date(byAdding: .day, value: -recentDays, to: Date()) {
                opts.predicate = NSPredicate(format: "creationDate >= %@", start as NSDate)
            }
            opts.fetchLimit = limit * 2
            let photos = PHAsset.fetchAssets(with: .image, options: opts)
            photos.enumerateObjects { asset, _, stop in
                if results.count >= limit {
                    stop.pointee = true
                    return
                }
                consider(asset)
            }
        }

        return results
    }

    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill
    ) async -> UIImage? {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            let lock = NSLock()
            var resumed = false
            func finish(_ image: UIImage?) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: image)
            }

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if cancelled || info?[PHImageErrorKey] != nil {
                    finish(nil)
                    return
                }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if image != nil {
                    finish(image)
                } else if !degraded {
                    finish(nil)
                }
            }
        }
    }

    func requestAnalysisImage(for asset: PHAsset) async -> UIImage? {
        let maxSide: CGFloat = 1280
        let w = CGFloat(asset.pixelWidth)
        let h = CGFloat(asset.pixelHeight)
        let scale = min(1, maxSide / max(w, h, 1))
        let size = CGSize(width: max(1, w * scale), height: max(1, h * scale))
        return await requestImage(for: asset, targetSize: size, contentMode: .aspectFit)
    }

    func deleteAssets(withLocalIds ids: [String]) async throws -> Int {
        // 二次保护：收藏永不删
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var toDelete: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in
            if asset.isFavorite { return }
            toDelete.append(asset)
        }
        guard !toDelete.isEmpty else { return 0 }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
            }) { success, error in
                if let error {
                    cont.resume(throwing: error)
                } else if success {
                    cont.resume()
                } else {
                    cont.resume(throwing: NSError(
                        domain: "PhotoJunkCleaner",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "删除失败"]
                    ))
                }
            }
        }
        return toDelete.count
    }
}
