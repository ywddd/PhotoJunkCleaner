import SwiftUI
import Photos
import UIKit

/// 异步加载 PHAsset 缩略图，用于相簿封面与网格
struct PhotoThumbnail: View {
    let asset: PHAsset?
    var size: CGFloat = 200

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .task(id: asset?.localIdentifier) {
            guard let asset else {
                image = nil
                return
            }
            let px = size * UIScreen.main.scale
            image = await PhotoLibraryService.shared.requestImage(
                for: asset,
                targetSize: CGSize(width: px, height: px)
            )
        }
    }
}
