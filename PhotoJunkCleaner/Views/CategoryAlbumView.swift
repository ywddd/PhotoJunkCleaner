import SwiftUI
import Photos

/// 某一分类下的网格相册：并排多列缩略图，点选勾选，支持大图预览
struct CategoryAlbumView: View {
    @ObservedObject var engine: ScanEngine
    let category: JunkCategory

    @State private var previewItem: JunkPhotoItem?
    @State private var showDeleteConfirm = false
    /// 默认约 3 列；可在工具栏切换更密/更疏
    @State private var gridMinWidth: CGFloat = 108

    private var items: [JunkPhotoItem] {
        engine.foundItems.filter { $0.category == category }
    }

    private var selectedInCategory: Int {
        items.filter(\.isSelected).count
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: gridMinWidth), spacing: 3)]
    }

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("此分类暂无照片")
                        .font(.headline)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(items) { item in
                            AlbumPhotoCell(
                                item: item,
                                onToggle: { engine.setSelected(id: item.id, selected: !item.isSelected) },
                                onPreview: { previewItem = item }
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(category.displayName)
                        .font(.headline)
                    Text("\(items.count) 张 · 已选 \(selectedInCategory)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("全选本类") { setAllInCategory(true) }
                    Button("取消本类") { setAllInCategory(false) }
                    Divider()
                    Button("大图（约 2 列）") { gridMinWidth = 160 }
                    Button("默认（约 3 列）") { gridMinWidth = 108 }
                    Button("密集（约 4 列）") { gridMinWidth = 78 }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("全选") { setAllInCategory(true) }
                Button("取消") { setAllInCategory(false) }
                Spacer()
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label(
                        "删除\(selectedInCategory > 0 ? " \(selectedInCategory)" : "")",
                        systemImage: "trash"
                    )
                }
                .disabled(selectedInCategory == 0 || engine.isDeleting)
            }
        }
        .confirmationDialog(
            "删除本类已选 \(selectedInCategory) 张？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除 \(selectedInCategory) 张", role: .destructive) {
                Task { try? await engine.deleteSelected() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅删除当前已勾选的照片，将进入系统「最近删除」。")
        }
        .sheet(item: $previewItem) { item in
            PhotoPreviewSheet(
                item: item,
                isSelected: item.isSelected,
                onToggle: {
                    engine.setSelected(id: item.id, selected: !item.isSelected)
                    if let updated = engine.foundItems.first(where: { $0.id == item.id }) {
                        previewItem = updated
                    }
                }
            )
        }
    }

    private func setAllInCategory(_ selected: Bool) {
        for item in items {
            engine.setSelected(id: item.id, selected: selected)
        }
    }
}

// MARK: - 网格单元格

private struct AlbumPhotoCell: View {
    let item: JunkPhotoItem
    let onToggle: () -> Void
    let onPreview: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onPreview) {
                PhotoThumbnail(asset: item.asset, size: 240)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggle) {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        item.isSelected ? Color.white : Color.white.opacity(0.9),
                        item.isSelected ? Color.accentColor : Color.black.opacity(0.35)
                    )
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack {
                Spacer()
                HStack {
                    Text("\(Int(item.confidence * 100))%")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                .padding(4)
            }
            .allowsHitTesting(false)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            if item.isSelected {
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
    }
}

// MARK: - 大图预览

private struct PhotoPreviewSheet: View {
    let item: JunkPhotoItem
    let isSelected: Bool
    let onToggle: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                PhotoThumbnail(asset: item.asset, size: 1200)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(item.category.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onToggle) {
                        Label(
                            isSelected ? "已选中" : "选中清理",
                            systemImage: isSelected ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.reasons.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                        Text(item.asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
        }
        .presentationDetents([.large])
    }
}
