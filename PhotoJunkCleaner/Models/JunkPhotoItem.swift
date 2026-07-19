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

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(processed) / Double(total)
    }
}

struct CategoryGroup: Identifiable {
    let category: JunkCategory
    var items: [JunkPhotoItem]

    var id: String { category.id }
    var selectedCount: Int { items.filter(\.isSelected).count }
}
