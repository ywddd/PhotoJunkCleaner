import SwiftUI
import Photos

struct ResultsView: View {
    @ObservedObject var engine: ScanEngine
    var onDelete: () -> Void
    var onRescan: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            List {
                ForEach(engine.groups) { group in
                    Section {
                        ForEach(group.items) { item in
                            JunkRow(
                                item: item,
                                onToggle: { selected in
                                    engine.setSelected(id: item.id, selected: selected)
                                }
                            )
                        }
                    } header: {
                        CategoryHeader(
                            group: group,
                            onSelectAll: { selected in
                                engine.setCategorySelected(group.category, selected: selected)
                            }
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)

            bottomBar
        }
    }

    private var summaryBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("候选 \(engine.totalCandidates) 张")
                    .font(.subheadline.bold())
                Text(engine.progress.phase)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("全选") { engine.selectAll(true) }
                .font(.caption.weight(.semibold))
            Button("全不选") { engine.selectAll(false) }
                .font(.caption)
            Button("重扫") { onRescan() }
                .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Text("已勾选 \(engine.selectedCount) 张 · 删除前会再次确认")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(role: .destructive, action: onDelete) {
                Label("清理已选 \(engine.selectedCount) 张", systemImage: "trash.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(engine.selectedCount == 0)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Header

private struct CategoryHeader: View {
    let group: CategoryGroup
    var onSelectAll: (Bool) -> Void

    var body: some View {
        HStack {
            Label(group.category.displayName, systemImage: group.category.systemImage)
                .foregroundStyle(group.category.tint)
                .font(.subheadline.weight(.semibold))
            Text("(\(group.items.count))")
                .foregroundStyle(.secondary)
            Spacer()
            let selected = group.selectedCount
            Text("\(selected)/\(group.items.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("全选") { onSelectAll(true) }
                .font(.caption2)
            Button("取消") { onSelectAll(false) }
                .font(.caption2)
        }
        .textCase(nil)
    }
}

// MARK: - Row

private struct JunkRow: View {
    let item: JunkPhotoItem
    var onToggle: (Bool) -> Void

    @State private var thumb: UIImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onToggle(!item.isSelected)
            } label: {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isSelected ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if item.isScreenshot {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 9, weight: .bold))
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.category.displayName)
                        .font(.subheadline.bold())
                    Spacer()
                    confidenceBadge
                }
                if !item.reasons.isEmpty {
                    Text(item.reasons.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let date = item.creationDate {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onToggle(!item.isSelected) }
        .task(id: item.assetLocalId) {
            await loadThumb()
        }
    }

    private var confidenceBadge: some View {
        Text(String(format: "%.0f%%", item.confidence * 100))
            .font(.caption2.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(item.category.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(item.category.tint)
    }

    private func loadThumb() async {
        guard let asset = item.asset else { return }
        let img = await PhotoLibraryService.shared.requestImage(
            for: asset,
            targetSize: CGSize(width: 160, height: 160)
        )
        await MainActor.run { thumb = img }
    }
}
