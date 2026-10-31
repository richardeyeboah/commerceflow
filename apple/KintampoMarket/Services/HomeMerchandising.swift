import Foundation

/// Home shelves, mirroring `lib/supabase/homepage-curation.ts` on the website:
/// staples pinned first, then a trending mix that leads with groceries and caps cosmetics.
enum HomeMerchandising {
    private static let staplePins: [(patterns: [String], limit: Int)] = [
        (["fufu"], 3), (["yam"], 1), (["plantain"], 2),
    ]

    private static let trendingSlots: [(category: String, limit: Int, keywords: [String])] = [
        ("Flours & Rice", 2, ["gari", "banku", "rice", "konkonte"]),
        ("Fresh Produce", 1, ["okra", "ugwu", "spinach"]),
        ("Beverages", 1, []),
        ("Spices", 1, []),
        ("Snack", 1, []),
        ("Meat and Seafood", 1, []),
        ("Bread", 1, []),
        ("Cosmetics", 1, []),
    ]

    /// In-stock, photographed, storefront-visible products, newest first.
    private static func pool(_ products: [Product]) -> [Product] {
        StorefrontCatalog.visible(products)
            .filter { $0.effectiveInStock && $0.primaryImageURL != nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func staples(from products: [Product]) -> [Product] {
        let candidates = pool(products)
        var used = Set<String>()
        var out: [Product] = []
        for pin in staplePins {
            let matches = candidates.filter { p in
                !used.contains(p.id) && pin.patterns.contains { p.name.lowercased().contains($0) }
            }
            for p in matches.prefix(pin.limit) {
                used.insert(p.id)
                out.append(p)
            }
        }
        return out
    }

    static func trending(from products: [Product], excluding: Set<String>, target: Int = 8) -> [Product] {
        let candidates = pool(products)
        var used = excluding
        var out: [Product] = []
        for slot in trendingSlots {
            let inCategory = candidates.filter { $0.category == slot.category && !used.contains($0.id) }
            let preferred = inCategory.filter { p in slot.keywords.contains { p.name.lowercased().contains($0) } }
            var seen = Set<String>()
            for p in (preferred + inCategory) where !seen.contains(p.id) {
                seen.insert(p.id)
                if seen.count > slot.limit { break }
                used.insert(p.id)
                out.append(p)
            }
        }
        for p in candidates where out.count < target && !used.contains(p.id) && p.category != "Cosmetics" {
            used.insert(p.id)
            out.append(p)
        }
        return out
    }
}
