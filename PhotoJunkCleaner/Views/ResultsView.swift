import SwiftUI
import Photos

/// 扫描结果：按分类展示「相簿封面」，点进分类再网格核对
struct ResultsView: View {
    @ObservedObject var engine: ScanEngine
    var onDelete: () -> Void
    var onRescan: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏摘要
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("按分类查看")
                        .font(.title2.weight(.bold))
                    Text("点进分类可网格并排核对，再决定删除")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("重新扫描", action: onRescan)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if engine.groups.isEmpty {
                Spacer()
                VStack(spacing: 12) {
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
                }
                Spacer()
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
                                    selectedCount: group.items.filter { $0.isSelected }.count,
                                    coverAsset: group.items.first?.asset
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                }
            }

            // 底部删除栏
            if engine.selectedCount > 0 {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Text("已选 \(engine.selectedCount) 张")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button("全部取消") {
                            engine.selectAll(false)
                        }
                        .font(.subheadline)
                        Button(role: .destructive, action: onDelete) {
                            Label("删除已选", systemImage: "trash.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                }
            }
        }
    }
}

// MARK: - 分类封面卡片

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
                    Text("\(selectedCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}
