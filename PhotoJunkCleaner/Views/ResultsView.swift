import SwiftUI
import Photos

/// 系统相册风格：分类 = 相簿，大封面 + 名称 + 张数
struct ResultsView: View {
    @ObservedObject var engine: ScanEngine
    var onDelete: () -> Void
    var onRescan: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("我的相簿")
                        .font(.title2.weight(.bold))
                    Spacer()
                    Button("重新扫描", action: onRescan)
                        .font(.subheadline)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

                if engine.groups.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 52, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("未发现可疑废图")
                            .font(.title3.weight(.semibold))
                        Text("可在设置中开启「扫描近期照片」、调低置信度后重试")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(engine.groups) { group in
                            NavigationLink {
                                CategoryAlbumView(engine: engine, category: group.category)
                            } label: {
                                SystemAlbumCell(
                                    title: group.category.displayName,
                                    count: group.items.count,
                                    selected: group.items.filter { $0.isSelected }.count,
                                    cover: group.items.first?.asset
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, engine.selectedCount > 0 ? 100 : 24)
                }
            }
        }
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) {
            if engine.selectedCount > 0 {
                HStack {
                    Text("已选择 \(engine.selectedCount) 项")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button("取消选择") { engine.selectAll(false) }
                        .font(.subheadline)
                    Button(role: .destructive, action: onDelete) {
                        Text("删除")
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
    }
}

/// 接近系统「相簿」封面：大方图 + 下方标题与数量
private struct SystemAlbumCell: View {
    let title: String
    let count: Int
    let selected: Int
    let cover: PHAsset?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.systemGray5))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    PhotoThumbnail(asset: cover, side: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .overlay(alignment: .topTrailing) {
                    if selected > 0 {
                        Text("\(selected)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule())
                            .padding(6)
                    }
                }

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("\(count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
