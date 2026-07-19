import SwiftUI
import Photos
import UIKit

/// 系统相册风格缩略图（铺满格子）
struct PhotoThumbnail: View {
    let asset: PHAsset?
    var side: CGFloat = 200

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemGray5)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .task(id: asset?.localIdentifier) {
            guard let asset else { image = nil; return }
            image = await PhotoLibraryService.shared.requestThumbnail(for: asset, side: max(side, 120))
        }
    }
}
