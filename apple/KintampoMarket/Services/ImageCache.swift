import Foundation
import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

/// Memory + disk URLCache so product photos are not re-downloaded every scroll.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSURL, PlatformImage>()
    private let session: URLSession

    private init() {
        memory.countLimit = 200
        memory.totalCostLimit = 40 * 1024 * 1024

        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024,
            diskPath: "kintampo-images"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 12
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)
    }

    func image(for url: URL) async -> PlatformImage? {
        let resolved = StorefrontCatalog.displayURL(url)
        let key = resolved as NSURL
        if let hit = memory.object(forKey: key) { return hit }

        do {
            let (data, response) = try await session.data(from: resolved)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let image = PlatformImage(data: data)
            else { return nil }
            memory.setObject(image, forKey: key, cost: data.count)
            return image
        } catch {
            return nil
        }
    }
}

struct CachedProductImage: View {
    let url: URL?
    @State private var image: PlatformImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Brand.surface
            if let image {
                #if os(macOS)
                Image(nsImage: image).resizable().scaledToFill()
                #else
                Image(uiImage: image).resizable().scaledToFill()
                #endif
            } else if failed || url == nil {
                Image(systemName: "bag.fill")
                    .font(.title2)
                    .foregroundStyle(Brand.red.opacity(0.35))
            } else {
                Rectangle().fill(Color.gray.opacity(0.08))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            image = nil
            failed = false
            guard let url else {
                failed = true
                return
            }
            let loaded = await ImageCache.shared.image(for: url)
            image = loaded
            failed = loaded == nil
        }
    }
}
