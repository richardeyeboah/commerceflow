import Foundation
import Observation

enum CatalogSort: String, CaseIterable, Identifiable {
    case newest, priceLow, priceHigh, name
    var id: String { rawValue }
    var label: String {
        switch self {
        case .newest: return "Newest"
        case .priceLow: return "Price ↑"
        case .priceHigh: return "Price ↓"
        case .name: return "Name"
        }
    }
    func apply(_ list: [Product]) -> [Product] {
        switch self {
        case .newest:
            return list.sorted { $0.createdAt > $1.createdAt }
        case .priceLow:
            return list.sorted { $0.price < $1.price }
        case .priceHigh:
            return list.sorted { $0.price > $1.price }
        case .name:
            return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
}

/// Shared catalog — one fetch, reused across Home + Shop. Avoids the slow double-load.
@Observable
@MainActor
final class CatalogStore {
    static let shared = CatalogStore()

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastFetchedAt: Date?

    private let cacheTTL: TimeInterval = 120

    var isFresh: Bool {
        guard let lastFetchedAt else { return false }
        return Date().timeIntervalSince(lastFetchedAt) < cacheTTL
    }

    func featured(limit: Int = 12) -> [Product] {
        Array(products.filter(\.effectiveInStock).prefix(limit))
    }

    func filtered(
        search: String = "",
        category: String? = nil,
        inStockOnly: Bool = false,
        sort: CatalogSort = .newest
    ) -> [Product] {
        var list = products
        if let category, !category.isEmpty {
            list = list.filter { $0.category == category }
        }
        if inStockOnly {
            list = list.filter(\.effectiveInStock)
        }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q)
                    || ($0.brand?.lowercased().contains(q) ?? false)
                    || $0.category.lowercased().contains(q)
            }
        }
        return sort.apply(list)
    }

    /// Warm cache at launch. Skips network if still fresh unless `force`.
    func loadIfNeeded(force: Bool = false) async {
        if !force, isFresh, !products.isEmpty { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Wide list fetch; filter test SKUs; search/category stay local for snappy UI.
            let fetched = try await SupabaseService.shared.fetchProducts(limit: 500, listMode: true)
            products = StorefrontCatalog.visible(fetched)
            lastFetchedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
            if products.isEmpty {
                products = []
            }
        }
    }
}
