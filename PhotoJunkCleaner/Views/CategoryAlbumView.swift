import SwiftUI
import Photos

/// 某个分类下的「相册」：网格并排，方便核对识别是否准确
struct CategoryAlbumView: View {
    @ObservedObject var engine: ScanEngine
    let category: JunkCategory

    @State private var columnCount: Int = 3
    @State private var previewItem: JunkPhotoItem?
    @State private var showDeleteConfirm = false

    private var items: [JunkPhotoItem] {
        engine.groups.first(where: { $0.category == category })?.items ?? []
    }

    private var selectedInCategory: Int {
        items.filter(\.isSelected).count
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 3), count: columnCount)
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
                    Text("返回后可重新扫描")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 3) {
                        ForEach(items) { item in
                            AlbumPhotoCell(
                                item: item,
                                onToggle: {
                                    engine.setSelected(id: item.id, selected: !item.isSelected)
                                },
                                onPreview: {
                                    previewItem = item
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 88)
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("列数", selection: $columnCount) {
                        Text("2 列").tag(2)
                        Text("3 列").tag(3)
                        Text("4 列").tag(4)
                    }
                    Divider()
                    Button {
                        engine.setCategorySelected(category, selected: true)
                    } label: {
                        Label("全选本类", systemImage: "checkmark.circle")
                    }
                    Button {
                        engine.setCategorySelected(category, selected: false)
                    } label: {
                        Label("清空本类", systemImage: "circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !items.isEmpty {
                HStack {
                    Text("本类 \(items.count) 张 · 已选 \(selectedInCategory)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(
                            selectedInCategory > 0 ? "删除 \(selectedInCategory)" : "删除",
                            systemImage: "trash"
                        )
                        .font(.subheadline.weight(.semibold))
                    }
                    .disabled(selectedInCategory == 0)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .confirmationDialog(
            "确认删除本类已选 \(selectedInCategory) 张？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除 \(selectedInCategory) 张", role: .destructive) {
                // 仅保留本类选中：先取消其他分类选中，再删
                let keep = Set(items.filter(\.isSelected).map(\.id))
                for g in engine.groups {
                    for it in g.items {
                        if g.category != category {
                            engine.setSelected(id: it.id, selected: false)
                        } else {
                            engine.setSelected(id: it.id, selected: keep.contains(it.id))
                        }
                    }
                }
                Task {
                    _ = await engine.deleteSelected()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将移入「最近删除」，30 天内可在系统相册恢复。")
        }
        .sheet(item: $previewItem) { item in
            PhotoPreviewSheet(
                item: item,
                isSelected: item.isSelected,
                onToggle: {
                    engine.setSelected(id: item.id, selected: !item.isSelected)
                    // 刷新 sheet 内状态：关闭再开较重，直接改 engine 即可
                    if let updated = items.first(where: { $0.id == item.id }) {
                        previewItem = updated
                    }
                }
            )
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
                        item.isSelected ? Color.white : Color.white.opacity(0.95),
                        item.isSelected ? Color.accentColor : Color.black.opacity(0.4)
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
                        if let date = item.asset.creationDate {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
        }
        .presentationDetents([.large])
    }
}
