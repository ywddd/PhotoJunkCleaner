import SwiftUI
import Photos

/// 扫描结果首页：像系统相册一样按「分类」展示封面与数量
struct ResultsView: View {
    @ObservedObject var engine: ScanEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false
    @State private var columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if engine.foundItems.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(engine.groups) { group in
                                NavigationLink {
                                    CategoryAlbumView(engine: engine, category: group.category)
                                } label: {
                                    CategoryAlbumCard(
                                        category: group.category,
                                        count: group.items.count,
                                        selectedCount: group.items.filter(\.isSelected).count,
                                        coverAsset: group.items.first?.asset
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("扫描结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            engine.selectAll(true)
                        } label: {
                            Label("全选默认清理项", systemImage: "checkmark.circle")
                        }
                        Button {
                            engine.selectAll(false)
                        } label: {
                            Label("全部取消", systemImage: "circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Text(selectionSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label(
                                "删除\(engine.selectedCount > 0 ? " \(engine.selectedCount)" : "")",
                                systemImage: "trash"
                            )
                        }
                        .disabled(engine.selectedCount == 0 || engine.isDeleting)
                    }
                }
            }
            .confirmationDialog(
                "确认删除 \(engine.selectedCount) 张照片？",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("删除 \(engine.selectedCount) 张", role: .destructive) {
                    Task {
                        try? await engine.deleteSelected()
                        if engine.foundItems.isEmpty {
                            dismiss()
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将移入「最近删除」，30 天内可在系统相册恢复。建议先点进各分类核对缩略图。")
            }
            .overlay {
                if engine.isDeleting {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView("正在删除…")
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
    }

    private var selectionSummary: String {
        let total = engine.foundItems.count
        let selected = engine.selectedCount
        if selected == 0 {
            return "共 \(total) 张 · 点分类查看"
        }
        return "已选 \(selected) / \(total)"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("没有发现可疑废图")
                .font(.title3.weight(.semibold))
            Text("可在设置里调低置信度或扩大扫描范围后重试")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 分类封面卡片（类似相册「相簿」）

private struct CategoryAlbumCard: View {
    let category: JunkCategory
    let count: Int
    let selectedCount: Int
    let coverAsset: PHAsset?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        PhotoThumbnail(asset: coverAsset, size: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 6) {
                    Image(systemName: category.systemImage)
                    Text("\(count)")
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(10)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(category.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if selectedCount > 0 {
                    Text("\(selectedCount) 选中")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        )
    }
}
