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
    private let storageKey = "lqam-cart"
    private let defaults: UserDefaults

    var itemCount: Int { items.reduce(0) { $0 + $1.quantity } }
    var subtotal: Double { items.reduce(0) { $0 + $1.lineTotal } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(_ product: Product, quantity: Int = 1) {
        guard quantity > 0, product.maxCartQuantity > 0 else { return }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        if let index = items.firstIndex(where: { $0.product.id == product.id }) {
            items[index] = CartItem(product: product, quantity: min(product.maxCartQuantity, items[index].quantity + min(quantity, 99)))
        } else {
            items.append(CartItem(product: product, quantity: min(quantity, product.maxCartQuantity)))
        }
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
