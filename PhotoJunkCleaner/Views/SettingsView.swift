import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var albums: [AlbumInfo] = []
    @State private var loadError: String?
    @State private var cloudTestResult: String = ""
    @State private var cloudTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("识别") {
                    Toggle(isOn: $settings.preciseMode) {
                        Label("精准识别（更慢更准）", systemImage: "wand.and.stars")
                    }
                    Text("关闭为快速模式：默认只做快速 OCR，二维码先检条码，大幅提速。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("云端视觉（可选）") {
                    Toggle("启用云端视觉 API", isOn: $settings.cloudVisionEnabled)
                    Text("兼容 OpenAI 视觉接口。默认：本地先扫；仅「截图存疑 / 弱分类」才上云，正常照片不会张张请求（否则 4000 张会极慢）。可设次数上限。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if settings.cloudVisionEnabled {
                        TextField("Base URL（如 https://api.openai.com/v1）", text: $settings.cloudBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        SecureField("API Key", text: $settings.cloudAPIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("模型名（如 gpt-4o-mini / grok-2-vision-1212）", text: $settings.cloudModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("代理（可选 http://host:port）", text: $settings.cloudProxyURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Toggle("仅本地不确定时调用（推荐）", isOn: $settings.cloudOnlyUncertain)
                        if !settings.cloudOnlyUncertain {
                            Text("关闭后会对更多截图上云，速度明显变慢、费用更高。")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Stepper(value: $settings.cloudMaxCallsPerScan, in: 5...500, step: 5) {
                            Text("单次扫描最多云端 \(settings.cloudMaxCallsPerScan) 次")
                        }
                        VStack(alignment: .leading) {
                            HStack {
                                Text("不确定阈值")
                                Spacer()
                                Text(String(format: "%.0f%%", settings.cloudUncertainThreshold * 100))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $settings.cloudUncertainThreshold, in: 0.3...0.85, step: 0.05)
                        }
                        Button("测试连接") {
                            testCloud()
                        }
                        if !cloudTestResult.isEmpty {
                            Text(cloudTestResult)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("扫描范围") {
                    Toggle("优先扫描截图", isOn: $settings.preferScreenshots)
                    Toggle("包含普通照片", isOn: $settings.includeRecent)
                    Toggle("扫描全部照片", isOn: $settings.scanAllPhotos)
                    if !settings.scanAllPhotos {
                        Picker("普通照片回溯", selection: $settings.recentDays) {
                            Text("近 90 天").tag(90)
                            Text("近 1 年").tag(365)
                            Text("近 3 年").tag(1095)
                            Text("不限日期").tag(0)
                        }
                    }
                    Picker("扫描上限", selection: $settings.scanLimit) {
                        Text("500 张").tag(500)
                        Text("1000 张").tag(1000)
                        Text("2000 张").tag(2000)
                        Text("5000 张").tag(5000)
                        Text("不限制（最多 2 万）").tag(0)
                    }
                    Text("相册总数与「本次会扫多少」不是一回事：默认只扫截图 + 一段时间的照片，并用上限保护性能。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("最低置信度")
                            Spacer()
                            Text(String(format: "%.0f%%", settings.minConfidence * 100))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.minConfidence, in: 0.3...0.9, step: 0.05)
                    }
                } header: {
                    Text("识别")
                } footer: {
                    Text("置信度越高候选越少但更准。二维码检测通常接近 100%。")
                }

                Section {
                    Toggle(isOn: $settings.protectFavorites) {
                        Label("保护「收藏」照片", systemImage: "heart.fill")
                    }
                } header: {
                    Text("安全保护")
                } footer: {
                    Text("开启后：收藏的照片不会进入扫描列表，删除时也会再次跳过。")
                }

                Section {
                    if let loadError {
                        Text(loadError)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else if albums.isEmpty {
                        Text("暂无相册或尚未授权")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(albums) { album in
                            Button {
                                settings.toggleAlbumProtection(album.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: settings.isAlbumProtected(album.id)
                                          ? "checkmark.shield.fill"
                                          : "shield")
                                        .foregroundStyle(settings.isAlbumProtected(album.id) ? .green : .secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(album.title)
                                            .foregroundStyle(.primary)
                                        Text("\(album.count) 张 · \(album.isUserAlbum ? "我的相册" : "智能相册")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if settings.isAlbumProtected(album.id) {
                                        Text("已保护")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("白名单相册（不扫描 / 不删除）")
                } footer: {
                    Text("点选相册加入白名单。该相册内所有照片会被跳过。已保护 \(settings.protectedAlbumIds.count) 个相册。")
                }

                Section("分类说明") {
                    Text("外卖 / 快递 / 二维码 / 支付：规则较完整。\n验证码与通知：含验证码 + 推送文案。\n聊天：聊天界面特征。\n其他疑似无用：电商订单、广告落地、临时页。\n普通截图：系统截图兜底（默认不勾选删除）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.7.0")
                    Text("本地 Vision OCR + 条码识别，不上传任何照片。删除走系统 Photos API，进入「最近删除」。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("隐私与权限") {
                    Text("需要「照片」读写权限。若为「有限访问」，请在系统设置中改为「所有照片」。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("打开系统设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                await loadAlbums()
            }
        }
    }

    private func testCloud() {
        cloudTesting = true
        cloudTestResult = "测试中…"
        Task {
            let msg = await VisionAPIService.shared.testConnection(settings: settings.cloudConfig())
            await MainActor.run {
                cloudTestResult = msg
                cloudTesting = false
            }
        }
    }

    private func loadAlbums() async {
        do {
            _ = try await PhotoLibraryService.shared.ensureAuthorized()
            albums = PhotoLibraryService.shared.listAlbums()
                .sorted { lhs, rhs in
                    // 已保护的靠前，再按数量
                    let lp = settings.isAlbumProtected(lhs.id)
                    let rp = settings.isAlbumProtected(rhs.id)
                    if lp != rp { return lp && !rp }
                    return lhs.count > rhs.count
                }
        } catch {
            loadError = error.localizedDescription
        }
    }
}
