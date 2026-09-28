import Foundation

enum StorefrontCatalog {
    /// Match web `isHiddenFromStorefront` — never show checkout-test SKUs in the app.
    static func isHidden(_ product: Product) -> Bool {
        let name = product.name.lowercased()
        let desc = (product.description ?? "").lowercased()
        if name.contains("payment test")
            || name.contains("checkout test")
            || name.contains("apple pay test")
            || name.hasPrefix("test item")
            || name.contains("($0.60)")
        {
            return true
        }
        if desc.contains("live checkout test"), name.contains("test") { return true }
        return false
    }

    static func visible(_ products: [Product]) -> [Product] {
        products.filter { !isHidden($0) }
    }

    /// Public product page on the live site — never share admin or local URLs.
    static func publicProductURL(id: String) -> URL {
        AppConfig.siteURL.appending(path: "products").appending(path: id)
    }

    /// Rewrite public storage URLs through the storefront proxy so CSP-safe photos load in-app.
    static func displayURL(_ url: URL) -> URL {
        let host = url.host?.lowercased() ?? ""
        let path = url.path
        guard host.hasSuffix("supabase.co"),
              let marker = path.range(of: "/product-images/")
        else { return url }
        let objectPath = String(path[marker.upperBound...])
        return AppConfig.siteURL
            .appending(path: "media")
            .appending(path: "product-images")
            .appending(path: objectPath)
    }
}
