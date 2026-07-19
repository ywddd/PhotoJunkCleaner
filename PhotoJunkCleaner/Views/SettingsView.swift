import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var albums: [AlbumInfo] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("扫描范围") {
                    Toggle("优先扫描截图", isOn: $settings.preferScreenshots)
                    Toggle("包含近期普通照片", isOn: $settings.includeRecent)
                    Picker("扫描上限", selection: $settings.scanLimit) {
                        Text("100").tag(100)
                        Text("300").tag(300)
                        Text("500").tag(500)
                        Text("1000").tag(1000)
                    }
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

                Section("关于") {
                    LabeledContent("版本", value: "1.1.0")
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
