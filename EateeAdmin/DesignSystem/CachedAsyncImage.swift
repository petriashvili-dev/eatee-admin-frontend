import SwiftUI
import UIKit
import ImageIO

private final class AdminImageCache {
    static let shared = AdminImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() { cache.countLimit = 200 }

    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func set(_ image: UIImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}

/// Асинхронное превью блюда с in-memory кэшем и фоновым декодированием.
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let maxSide: CGFloat?
    let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var uiImage: UIImage?

    init(url: URL?, maxSide: CGFloat? = nil, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.maxSide = maxSide
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage).resizable()
            } else {
                placeholder()
            }
        }
        .task(id: url) { await loadImage() }
    }

    private func loadImage() async {
        uiImage = nil
        guard let url else { return }

        let maxPixels = maxSide.map { Int($0 * displayScale) }
        let key = maxPixels.map { "\(url.absoluteString)|\($0)" } ?? url.absoluteString
        if let cached = AdminImageCache.shared.image(for: key) {
            uiImage = cached
            return
        }

        guard let data = try? await URLSession.shared.data(from: url).0 else { return }
        let image = await Task.detached(priority: .utility) {
            Self.decode(data: data, maxPixels: maxPixels)
        }.value
        guard !Task.isCancelled, let image else { return }
        AdminImageCache.shared.set(image, for: key)
        uiImage = image
    }

    nonisolated private static func decode(data: Data, maxPixels: Int?) -> UIImage? {
        guard let maxPixels,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels
              ] as CFDictionary)
        else {
            return UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}
