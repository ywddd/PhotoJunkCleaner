import Foundation
import Photos
import UIKit

struct JunkPhotoItem: Identifiable, Hashable {
    let id: String
    let assetLocalId: String
    let category: JunkCategory
    let confidence: Double
    let reasons: [String]
    let creationDate: Date?
    let isScreenshot: Bool
    let pixelWidth: Int
    let pixelHeight: Int

    /// 用户是否勾选删除（UI 层可变）
    var isSelected: Bool

    var asset: PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalId], options: nil).firstObject
    }

    static func == (lhs: JunkPhotoItem, rhs: JunkPhotoItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ScanProgress: Equatable {
    var total: Int = 0
    var processed: Int = 0
    var found: Int = 0
    var phase: String = "准备中"
    /// 扫描开始时间（用于速度/ETA）
    var startedAt: Date? = nil
    /// 张/秒
    var itemsPerSecond: Double = 0
    /// 预计剩余秒数；nil 表示尚不可估
    var etaSeconds: Double? = nil

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(processed) / Double(total))
    }

    var speedText: String {
        guard itemsPerSecond > 0.05 else { return "计算速度…" }
        if itemsPerSecond >= 10 {
            return String(format: "%.0f 张/秒", itemsPerSecond)
        }
        return String(format: "%.1f 张/秒", itemsPerSecond)
    }

    var etaText: String {
        guard let eta = etaSeconds, eta.isFinite, eta > 0 else {
            return processed > 0 ? "估算中…" : "—"
        }
        if eta < 60 { return "约 \(Int(eta.rounded())) 秒" }
        let m = Int(eta / 60)
        let s = Int(eta.truncatingRemainder(dividingBy: 60))
        if m < 60 { return "约 \(m) 分 \(s) 秒" }
        let h = m / 60
        let mm = m % 60
        return "约 \(h) 小时 \(mm) 分"
    }
}

struct CategoryGroup: Identifiable {
    let category: JunkCategory
    var items: [JunkPhotoItem]

    var id: String { category.id }
    var selectedCount: Int { items.filter(\.isSelected).count }
}
