import Foundation
import Combine

/// 用户偏好：扫描范围 + 白名单保护
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var preferScreenshots: Bool {
        didSet { defaults.set(preferScreenshots, forKey: Keys.preferScreenshots) }
    }
    @Published var includeRecent: Bool {
        didSet { defaults.set(includeRecent, forKey: Keys.includeRecent) }
    }
    @Published var scanLimit: Int {
        didSet { defaults.set(scanLimit, forKey: Keys.scanLimit) }
    }
    @Published var minConfidence: Double {
        didSet { defaults.set(minConfidence, forKey: Keys.minConfidence) }
    }
    /// 精准识别：慢一倍左右，二次 accurate OCR
    @Published var preciseMode: Bool {
        didSet { defaults.set(preciseMode, forKey: Keys.preciseMode) }
    }
    /// 永不删除 / 不扫描「收藏」
    @Published var protectFavorites: Bool {
        didSet { defaults.set(protectFavorites, forKey: Keys.protectFavorites) }
    }
    /// 跳过用户标记为白名单的相册（localIdentifier 列表）
    @Published var protectedAlbumIds: Set<String> {
        didSet {
            defaults.set(Array(protectedAlbumIds), forKey: Keys.protectedAlbumIds)
        }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let preferScreenshots = "settings.preferScreenshots"
        static let includeRecent = "settings.includeRecent"
        static let scanLimit = "settings.scanLimit"
        static let minConfidence = "settings.minConfidence"
        static let protectFavorites = "settings.protectFavorites"
        static let protectedAlbumIds = "settings.protectedAlbumIds"
        static let settingsVersion = "settings.version"
        static let preciseMode = "settings.preciseMode"
    }

    private init() {
        // v2：默认扫截图+近期照片、更低置信度、更大扫描上限
        let ver = defaults.integer(forKey: Keys.settingsVersion)
        if ver < 2 {
            defaults.set(true, forKey: Keys.includeRecent)
            defaults.set(800, forKey: Keys.scanLimit)
            defaults.set(0.32, forKey: Keys.minConfidence)
            defaults.set(2, forKey: Keys.settingsVersion)
        }
        // v3：默认快速模式 + 更合理置信度，避免把所有截图堆进「普通截图」
        if defaults.integer(forKey: Keys.settingsVersion) < 3 {
            defaults.set(false, forKey: Keys.preciseMode)
            defaults.set(0.40, forKey: Keys.minConfidence)
            defaults.set(500, forKey: Keys.scanLimit)
            defaults.set(3, forKey: Keys.settingsVersion)
        }
        preferScreenshots = defaults.object(forKey: Keys.preferScreenshots) as? Bool ?? true
        includeRecent = defaults.object(forKey: Keys.includeRecent) as? Bool ?? true
        scanLimit = defaults.object(forKey: Keys.scanLimit) as? Int ?? 800
        minConfidence = defaults.object(forKey: Keys.minConfidence) as? Double ?? 0.40
        preciseMode = defaults.object(forKey: Keys.preciseMode) as? Bool ?? false
        protectFavorites = defaults.object(forKey: Keys.protectFavorites) as? Bool ?? true
        if let arr = defaults.array(forKey: Keys.protectedAlbumIds) as? [String] {
            protectedAlbumIds = Set(arr)
        } else {
            protectedAlbumIds = []
        }
    }

    func toggleAlbumProtection(_ albumId: String) {
        if protectedAlbumIds.contains(albumId) {
            protectedAlbumIds.remove(albumId)
        } else {
            protectedAlbumIds.insert(albumId)
        }
    }

    func isAlbumProtected(_ albumId: String) -> Bool {
        protectedAlbumIds.contains(albumId)
    }
}

struct AlbumInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let count: Int
    let isUserAlbum: Bool
}
