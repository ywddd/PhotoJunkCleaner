import SwiftUI
import Photos
import UIKit

/// 异步加载系统相册缩略图
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
            let scale = UIScreen.main.scale
            let target = CGSize(width: size * scale, height: size * scale)
            image = await PhotoLibraryService.shared.requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill
            )
        }
    }
}
