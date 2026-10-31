import Foundation
import Observation
#if os(iOS)
import UIKit
#endif

@Observable
@MainActor
final class CartStore {
    static let shared = CartStore()

    private(set) var items: [CartItem] = []
    /// Set when `refreshFromStore` removed or repriced something; shown at the top of the cart.
    var refreshNotice: String?
    /// Most recent add, for the "Added to cart" toast. `token` changes on every add.
    private(set) var lastAdded: (name: String, token: Int)?
    private let storageKey = "lqam-cart"
    private let defaults: UserDefaults

    var itemCount: Int { items.reduce(0) { $0 + $1.quantity } }
    var subtotal: Double { items.reduce(0) { $0 + $1.lineTotal } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// `toast: false` for screens that confirm the add themselves (product page).
    func add(_ product: Product, quantity: Int = 1, toast: Bool = true) {
        guard quantity > 0, product.maxCartQuantity > 0 else { return }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        if let index = items.firstIndex(where: { $0.product.id == product.id }) {
            items[index] = CartItem(product: product, quantity: min(product.maxCartQuantity, items[index].quantity + min(quantity, 99)))
        } else {
            items.append(CartItem(product: product, quantity: min(quantity, product.maxCartQuantity)))
        }
        if toast { lastAdded = (product.name, (lastAdded?.token ?? 0) + 1) }
        persist()
    }

    func setQuantity(productID: String, quantity: Int) {
        guard let index = items.firstIndex(where: { $0.product.id == productID }) else { return }
        if quantity <= 0 {
            items.remove(at: index)
        } else {
            items[index].quantity = min(quantity, items[index].product.maxCartQuantity)
        }
        persist()
    }

    func remove(at offsets: IndexSet) {
        let ids = Set(offsets.compactMap { items.indices.contains($0) ? items[$0].product.id : nil })
        items.removeAll { ids.contains($0.product.id) }
        persist()
    }

    func remove(productID: String) {
        items.removeAll { $0.product.id == productID }
        persist()
    }

    func removePurchased(_ purchased: [CartItem]) {
        let quantities = Dictionary(purchased.map { ($0.product.id, $0.quantity) }, uniquingKeysWith: +)
        items = items.compactMap { item in
            let remaining = item.quantity - (quantities[item.product.id] ?? 0)
            return remaining > 0 ? CartItem(product: item.product, quantity: remaining) : nil
        }
        persist()
    }

    /// Re-checks saved items against the live store: drops products that no longer exist or are
    /// hidden, and refreshes price and stock so the cart never shows stale totals.
    /// Returns a short note for the customer when something changed.
    func refreshFromStore() async {
        if let note = await reconcileWithStore() { refreshNotice = note }
    }

    private func reconcileWithStore() async -> String? {
        let ids = items.map(\.product.id)
        guard !ids.isEmpty,
              let fresh = try? await SupabaseService.shared.fetchProductsByIDs(ids)
        else { return nil }
        let live = Dictionary(uniqueKeysWithValues: StorefrontCatalog.visible(fresh).map { ($0.id, $0) })
        var removed = 0
        var repriced = 0
        let updated: [CartItem] = items.compactMap { item in
            guard let product = live[item.product.id] else { removed += 1; return nil }
            let quantity = min(item.quantity, product.maxCartQuantity)
            guard quantity > 0 else { removed += 1; return nil }
            if product.price != item.product.price { repriced += 1 }
            return CartItem(product: product, quantity: quantity)
        }
        guard updated != items else { return nil }
        items = updated
        persist()
        var notes: [String] = []
        if removed > 0 { notes.append("\(removed) item\(removed == 1 ? " is" : "s are") no longer available and \(removed == 1 ? "was" : "were") removed") }
        if repriced > 0 { notes.append("\(repriced) price\(repriced == 1 ? "" : "s") changed") }
        return notes.isEmpty ? nil : notes.joined(separator: "; ") + "."
    }

    func clear() {
        items = []
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CartItem].self, from: data)
        else { return }
        items = decoded.compactMap { item in
            let quantity = min(item.quantity, item.product.maxCartQuantity)
            return quantity > 0 ? CartItem(product: item.product, quantity: quantity) : nil
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
