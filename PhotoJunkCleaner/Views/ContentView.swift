import SwiftUI

struct ContentView: View {
    @StateObject private var engine = ScanEngine()
    @StateObject private var settings = AppSettings.shared
    @State private var showConfirmDelete = false
    @State private var showSettings = false
    @State private var showResultAlert = false
    @State private var resultMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景渐变
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.12),
                        Color(.systemBackground),
                        Color.purple.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Group {
                    if engine.isScanning {
                        ScanningView(engine: engine)
                    } else if engine.groups.isEmpty {
                        HomeEmptyView(
                            settings: settings,
                            errorMessage: engine.errorMessage,
                            onStart: startScan
                        )
                    } else {
                        ResultsView(
                            engine: engine,
                            onDelete: { showConfirmDelete = true },
                            onRescan: startScan
                        )
                    }
                }
            }
            .navigationTitle("废图清理")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .confirmationDialog(
                "确认删除 \(engine.selectedCount) 张照片？",
                isPresented: $showConfirmDelete,
                titleVisibility: .visible
            ) {
                Button("删除 \(engine.selectedCount) 张", role: .destructive) {
                    Task { await performDelete() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将移入「最近删除」，30 天内可恢复。收藏与白名单相册中的照片不会被删除。")
            }
            .alert("完成", isPresented: $showResultAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(resultMessage)
            }
        }
    }

    private func startScan() {
        engine.minConfidence = settings.minConfidence
        engine.startScan(
            preferScreenshots: settings.preferScreenshots,
            includeRecentPhotos: settings.includeRecent,
            limit: settings.scanLimit
        )
    }

    private func performDelete() async {
        let result = await engine.deleteSelected()
        switch result {
        case .success(let n):
            resultMessage = "已删除 \(n) 张。可在「照片 → 最近删除」中恢复。"
            showResultAlert = true
        case .failure(let err):
            resultMessage = err.localizedDescription
            showResultAlert = true
        }
    }
}

// MARK: - Home

private struct HomeEmptyView: View {
    @ObservedObject var settings: AppSettings
    var errorMessage: String?
    var onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.35), Color.purple.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .blur(radius: 2)
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.accentColor, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolRenderingMode(.hierarchical)
                }
                .padding(.top, 36)

                Text("智能识别废图")
                    .font(.title.bold())

                Text("本地识别外卖、快递、二维码、支付、验证码等截图。删除前二次确认；收藏与白名单相册自动跳过。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                if let errorMessage, !errorMessage.isEmpty {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: $settings.preferScreenshots) {
                        Label("优先扫描截图", systemImage: "camera.viewfinder")
                    }
                    Toggle(isOn: $settings.includeRecent) {
                        Label("扫描近期普通照片", systemImage: "photo.on.rectangle")
                    }
                    Toggle(isOn: $settings.protectFavorites) {
                        Label("保护收藏（永不删）", systemImage: "heart.fill")
                    }
                    HStack {
                        Label("最多扫描", systemImage: "number")
                        Spacer()
                        Picker("", selection: $settings.scanLimit) {
                            Text("100").tag(100)
                            Text("300").tag(300)
                            Text("500").tag(500)
                            Text("1000").tag(1000)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal)

                Button(action: onStart) {
                    Label("开始扫描", systemImage: "magnifyingglass")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                categoryLegend
                    .padding(.bottom, 48)
            }
        }
    }

    private var categoryLegend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("可识别类型")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 8)], spacing: 8) {
                ForEach(JunkCategory.allCases) { cat in
                    Label(cat.displayName, systemImage: cat.systemImage)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(cat.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(cat.tint)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Scanning

private struct ScanningView: View {
    @ObservedObject var engine: ScanEngine

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 10)
                    .frame(width: 120, height: 120)
                Circle()
                    .trim(from: 0, to: max(0.02, engine.progress.fraction))
                    .stroke(
                        AngularGradient(
                            colors: [.accentColor, .purple, .accentColor],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.25), value: engine.progress.fraction)

                Text("\(Int(engine.progress.fraction * 100))%")
                    .font(.title2.monospacedDigit().bold())
            }

            Text(engine.progress.phase)
            Text("锁屏后系统会再给一小段后台时间；彻底杀进程会中断。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("已处理 \(engine.progress.processed) / \(engine.progress.total) · 命中 \(engine.progress.found)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("取消", role: .destructive) {
                engine.cancel()
            }
            .padding(.top, 8)

            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
