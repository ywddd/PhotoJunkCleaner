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
    /// 扫描普通照片时回溯天数；0 = 不限日期（仍受 scanLimit 约束）
    @Published var recentDays: Int {
        didSet { defaults.set(recentDays, forKey: Keys.recentDays) }
    }
    /// true = 扫描图库全部图片（最慢，仍受 scanLimit 截断；scanLimit<=0 表示不截断）
    @Published var scanAllPhotos: Bool {
        didSet { defaults.set(scanAllPhotos, forKey: Keys.scanAllPhotos) }
    }
    @Published var minConfidence: Double {
        didSet { defaults.set(minConfidence, forKey: Keys.minConfidence) }
    }
    /// 精准识别：慢一倍左右，二次 accurate OCR
    @Published var preciseMode: Bool {
        didSet { defaults.set(preciseMode, forKey: Keys.preciseMode) }
    }
    /// 使用内置 MobileNetV2 场景辅助（关则仅系统 Vision + OCR）
    @Published var useLocalML: Bool {
        didSet { defaults.set(useLocalML, forKey: Keys.useLocalML) }
    }
    /// 参与结果展示/收录的分类（rawValue）；空集合视为全部开启
    @Published var enabledCategoryIds: Set<String> {
        didSet { defaults.set(Array(enabledCategoryIds), forKey: Keys.enabledCategoryIds) }
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

    // MARK: - 云端视觉（可选，OpenAI 兼容）
    @Published var cloudVisionEnabled: Bool {
        didSet { defaults.set(cloudVisionEnabled, forKey: Keys.cloudVisionEnabled) }
    }
    @Published var cloudBaseURL: String {
        didSet { defaults.set(cloudBaseURL, forKey: Keys.cloudBaseURL) }
    }
    @Published var cloudAPIKey: String {
        didSet { defaults.set(cloudAPIKey, forKey: Keys.cloudAPIKey) }
    }
    @Published var cloudProxyURL: String {
        didSet { defaults.set(cloudProxyURL, forKey: Keys.cloudProxyURL) }
    }
    @Published var cloudModel: String {
        didSet { defaults.set(cloudModel, forKey: Keys.cloudModel) }
    }
    /// 仅本地不确定时调用云端
    @Published var cloudOnlyUncertain: Bool {
        didSet { defaults.set(cloudOnlyUncertain, forKey: Keys.cloudOnlyUncertain) }
    }
    @Published var cloudMaxCallsPerScan: Int {
        didSet { defaults.set(cloudMaxCallsPerScan, forKey: Keys.cloudMaxCallsPerScan) }
    }
    @Published var cloudUncertainThreshold: Double {
        didSet { defaults.set(cloudUncertainThreshold, forKey: Keys.cloudUncertainThreshold) }
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
        static let useLocalML = "settings.useLocalML"
        static let enabledCategoryIds = "settings.enabledCategoryIds"
        static let recentDays = "settings.recentDays"
        static let scanAllPhotos = "settings.scanAllPhotos"
        static let cloudVisionEnabled = "settings.cloudVisionEnabled"
        static let cloudBaseURL = "settings.cloudBaseURL"
        static let cloudAPIKey = "settings.cloudAPIKey"
        static let cloudProxyURL = "settings.cloudProxyURL"
        static let cloudModel = "settings.cloudModel"
        static let cloudOnlyUncertain = "settings.cloudOnlyUncertain"
        static let cloudMaxCallsPerScan = "settings.cloudMaxCallsPerScan"
        static let cloudUncertainThreshold = "settings.cloudUncertainThreshold"
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
        // v4：可选扫更多 / 全部照片
        if defaults.integer(forKey: Keys.settingsVersion) < 4 {
            defaults.set(365, forKey: Keys.recentDays)
            defaults.set(false, forKey: Keys.scanAllPhotos)
            defaults.set(2000, forKey: Keys.scanLimit)
            defaults.set(4, forKey: Keys.settingsVersion)
        }
        // v5：放宽默认阈值 + 默认开本地 ML，解决「0 命中」过严问题
        if defaults.integer(forKey: Keys.settingsVersion) < 5 {
            defaults.set(0.32, forKey: Keys.minConfidence)
            defaults.set(true, forKey: Keys.useLocalML)
            defaults.set(false, forKey: Keys.preciseMode)
            defaults.set(5, forKey: Keys.settingsVersion)
        }
        preferScreenshots = defaults.object(forKey: Keys.preferScreenshots) as? Bool ?? true
        includeRecent = defaults.object(forKey: Keys.includeRecent) as? Bool ?? true
        scanLimit = defaults.object(forKey: Keys.scanLimit) as? Int ?? 2000
        recentDays = defaults.object(forKey: Keys.recentDays) as? Int ?? 365
        scanAllPhotos = defaults.object(forKey: Keys.scanAllPhotos) as? Bool ?? false
        minConfidence = defaults.object(forKey: Keys.minConfidence) as? Double ?? 0.32
        preciseMode = defaults.object(forKey: Keys.preciseMode) as? Bool ?? false
        useLocalML = defaults.object(forKey: Keys.useLocalML) as? Bool ?? true
        if let arr = defaults.array(forKey: Keys.enabledCategoryIds) as? [String], !arr.isEmpty {
            enabledCategoryIds = Set(arr)
        } else {
            enabledCategoryIds = Set(JunkCategory.allCases.map(\.rawValue))
        }
        protectFavorites = defaults.object(forKey: Keys.protectFavorites) as? Bool ?? true
        if let arr = defaults.array(forKey: Keys.protectedAlbumIds) as? [String] {
            protectedAlbumIds = Set(arr)
        } else {
            protectedAlbumIds = []
        }

        cloudVisionEnabled = defaults.object(forKey: Keys.cloudVisionEnabled) as? Bool ?? false
        cloudBaseURL = defaults.string(forKey: Keys.cloudBaseURL) ?? "https://api.openai.com/v1"
        cloudAPIKey = defaults.string(forKey: Keys.cloudAPIKey) ?? ""
        cloudProxyURL = defaults.string(forKey: Keys.cloudProxyURL) ?? ""
        cloudModel = defaults.string(forKey: Keys.cloudModel) ?? "gpt-4o-mini"
        cloudOnlyUncertain = defaults.object(forKey: Keys.cloudOnlyUncertain) as? Bool ?? true
        cloudMaxCallsPerScan = defaults.object(forKey: Keys.cloudMaxCallsPerScan) as? Int ?? 30
        cloudUncertainThreshold = defaults.object(forKey: Keys.cloudUncertainThreshold) as? Double ?? 0.55
    }

    func cloudConfig() -> CloudVisionConfig {
        CloudVisionConfig(
            enabled: cloudVisionEnabled,
            baseURL: cloudBaseURL,
            apiKey: cloudAPIKey,
            proxyURL: cloudProxyURL,
            model: cloudModel,
            onlyUncertain: cloudOnlyUncertain,
            maxCallsPerScan: cloudMaxCallsPerScan,
            uncertainThreshold: cloudUncertainThreshold
        )
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

    func isCategoryEnabled(_ category: JunkCategory) -> Bool {
        // 空 = 全部
        if enabledCategoryIds.isEmpty { return true }
        return enabledCategoryIds.contains(category.rawValue)
    }

    func setCategoryEnabled(_ category: JunkCategory, enabled: Bool) {
        if enabledCategoryIds.isEmpty {
            enabledCategoryIds = Set(JunkCategory.allCases.map(\.rawValue))
        }
        if enabled {
            enabledCategoryIds.insert(category.rawValue)
        } else {
            enabledCategoryIds.remove(category.rawValue)
        }
        // 不允许全关
        if enabledCategoryIds.isEmpty {
            enabledCategoryIds = Set(JunkCategory.allCases.map(\.rawValue))
        }
    }

    func enableAllCategories() {
        enabledCategoryIds = Set(JunkCategory.allCases.map(\.rawValue))
    }
}


struct AlbumInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let count: Int
    let isUserAlbum: Bool
}
