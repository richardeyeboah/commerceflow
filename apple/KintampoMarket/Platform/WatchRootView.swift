import SwiftUI

/// Apple Watch — quick cart count, track order, open shop on phone.
struct WatchRootView: View {
    @Bindable private var cart = CartStore.shared
    @Bindable private var catalog = CatalogStore.shared
    @State private var tracker = OrderTrackViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Shop") {
                    if catalog.products.isEmpty {
                        Button("Load products") { Task { await catalog.reload() } }
                    }
                    ForEach(Array(catalog.products.filter(\.effectiveInStock).prefix(12))) { product in
                        Button {
                            cart.add(product, quantity: 1)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(product.name).lineLimit(2)
                                Text(product.displayPrice)
                            }
                        }
                    }
                }

                Section("Cart") {
                    LabeledContent("Items", value: "\(cart.itemCount)")
                    LabeledContent("Subtotal", value: String(format: "$%.2f", cart.subtotal))
                    if cart.itemCount > 0 {
                        Button("Clear cart", role: .destructive) { cart.clear() }
                    }
                }

                Section("Track") {
                    TextField("LQ-####", text: $tracker.orderID)
                    TextField("Email", text: $tracker.email)
                    Button("Track") {
                        Task { await tracker.track() }
                    }
                    if let order = tracker.order {
                        Text(order.status.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                    }
                }

                Section {
                    Text("Checkout stays on iPhone.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Kintampo")
            .task { await catalog.loadIfNeeded() }
        }
    }
}
