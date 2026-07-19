import SwiftUI
import Photos

/// 系统相册风格：全宽无缝 3 列网格
struct CategoryAlbumView: View {
    @ObservedObject var engine: ScanEngine
    let category: JunkCategory

    @State private var columns: Int = 3
    @State private var preview: JunkPhotoItem?
    @State private var confirmDelete = false

    private var items: [JunkPhotoItem] {
        engine.groups.first(where: { $0.category == category })?.items ?? []
    }

    private var selectedCount: Int {
        items.filter { $0.isSelected }.count
    }

    private var grid: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: columns)
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentPlaceholder()
            } else {
                ScrollView {
                    LazyVGrid(columns: grid, spacing: 2) {
                        ForEach(items) { item in
                            SystemGridCell(
                                item: item,
                                onTap: { preview = item },
                                onToggle: {
                                    engine.setSelected(id: item.id, selected: !item.isSelected)
                                }
                            )
                        }
                    }
                    .padding(.bottom, 72)
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("每行", selection: $columns) {
                        Text("2 列").tag(2)
                        Text("3 列").tag(3)
                        Text("4 列").tag(4)
                        Text("5 列").tag(5)
                    }
                    Divider()
                    Button("选择本类全部") {
                        engine.setCategorySelected(category, selected: true)
                    }
                    Button("取消本类选择") {
                        engine.setCategorySelected(category, selected: false)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selectedCount > 0 {
                HStack {
                    Text("已选择 \(selectedCount) 项")
                        .font(.subheadline)
                    Spacer()
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 36)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .confirmationDialog(
            "删除 \(selectedCount) 张照片？",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("删除照片", role: .destructive) {
                deleteSelectedInCategory()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这些项目将从你的 iPhone 上删除，并可在「最近删除」中恢复。")
        }
        .fullScreenCover(item: $preview) { item in
            SystemPreview(
                item: item,
                isSelected: Binding(
                    get: {
                        engine.groups
                            .flatMap(\.items)
                            .first(where: { $0.id == item.id })?
                            .isSelected ?? item.isSelected
                    },
                    set: { engine.setSelected(id: item.id, selected: $0) }
                ),
                onClose: { preview = nil }
            )
        }
    }

    private func deleteSelectedInCategory() {
        let keep = Set(items.filter { $0.isSelected }.map { $0.id })
        for g in engine.groups {
            for it in g.items {
                if g.category != category {
                    engine.setSelected(id: it.id, selected: false)
                } else {
                    engine.setSelected(id: it.id, selected: keep.contains(it.id))
                }
            }
        }
        Task { _ = await engine.deleteSelected() }
    }
}

private struct ContentPlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("无照片")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SystemGridCell: View {
    let item: JunkPhotoItem
    let onTap: () -> Void
    let onToggle: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                Color.clear
                    .aspectRatio(1, contentMode: .fill)
                    .overlay {
                        PhotoThumbnail(asset: item.asset, side: 280)
                    }
                    .clipped()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggle) {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        item.isSelected ? Color.white : Color.white.opacity(0.95),
                        item.isSelected ? Color.blue : Color.black.opacity(0.35)
                    )
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            if item.isSelected {
                Rectangle().strokeBorder(Color.blue, lineWidth: 3)
            }
        }
    }
}

private struct SystemPreview: View {
    let item: JunkPhotoItem
    @Binding var isSelected: Bool
    let onClose: () -> Void

    private var reason: String {
        item.reasons.joined(separator: " · ")
    }

    private var dateText: String {
        guard let d = item.creationDate else { return "" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                PhotoThumbnail(asset: item.asset, side: 1400)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(item.category.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成", action: onClose)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSelected.toggle()
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if !dateText.isEmpty {
                        Text(dateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(reason.isEmpty ? "置信度 \(Int(item.confidence * 100))%" : reason)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.black.opacity(0.55))
            }
        }
    }
}
