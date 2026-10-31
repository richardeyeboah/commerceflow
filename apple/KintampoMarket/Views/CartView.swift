import SwiftUI

struct CartView: View {
    @Bindable private var cart = CartStore.shared

    private var money: (Double) -> String { { String(format: "$%.2f", $0) } }

    var body: some View {
        Group {
            if cart.items.isEmpty {
                ContentUnavailableView {
                    Label("Your cart is empty", systemImage: "cart")
                } description: {
                    if let notice = cart.refreshNotice {
                        Text("Your cart was updated: \(notice)")
                    } else {
                        Text("Add items from the shop. Free pickup in Columbus.")
                    }
                } actions: {
                    Button("Browse shop") {
                        cart.refreshNotice = nil
                        AppRouter.shared.requestedTab = 1
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: 260)
                }
            } else {
                List {
                    if let notice = cart.refreshNotice {
                        Section {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "info.circle.fill").foregroundStyle(Brand.gold)
                                Text("Your cart was updated: \(notice)").font(.footnote)
                                Spacer(minLength: 0)
                                Button {
                                    cart.refreshNotice = nil
                                } label: {
                                    Image(systemName: "xmark").font(.caption.weight(.bold))
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Dismiss")
                            }
                        }
                    }
                    Section {
                        FreeShippingProgress(subtotal: cart.subtotal)
                    }
                    Section {
                        ForEach(cart.items) { item in
                            CartRow(item: item)
                        }
                        .onDelete { indexSet in cart.remove(at: indexSet) }
                    } footer: {
                        Text("Swipe left to remove an item.")
                    }

                    Section {
                        LabeledContent("Items", value: "\(cart.itemCount)")
                        LabeledContent("Subtotal") {
                            Text(money(cart.subtotal))
                                .fontWeight(.semibold)
                                .foregroundStyle(Brand.red)
                                .monospacedDigit()
                        }
                        Text("Tax and shipping are calculated at checkout.")
                            .font(.caption)
                            .foregroundStyle(Brand.inkMuted)
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
                .scrollContentBackground(.hidden)
                .background(Brand.surface)
                #if os(iOS) || os(macOS)
                .safeAreaInset(edge: .bottom) {
                    NavigationLink {
                        CheckoutView()
                    } label: {
                        HStack {
                            Text("Checkout")
                            Spacer()
                            Text(money(cart.subtotal)).monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding()
                    .background(.ultraThinMaterial)
                }
                #endif
            }
        }
        .navigationTitle("Cart")
        .task { await cart.refreshFromStore() }
        .refreshable { await cart.refreshFromStore() }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !cart.items.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear", role: .destructive) { cart.clear() }
                }
            }
        }
    }
}

private struct CartRow: View {
    let item: CartItem
    @Bindable private var cart = CartStore.shared

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: item.product) {
                CachedProductImage(url: item.product.primaryImageURL)
                    .frame(width: 60, height: 60)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.product.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Brand.ink)
                    .lineLimit(2)
                if let pack = item.product.packLabel, !pack.isEmpty {
                    Text(pack).font(.caption).foregroundStyle(Brand.inkMuted)
                }
                HStack(spacing: 6) {
                    Text(item.product.displayPrice)
                        .font(.caption)
                        .foregroundStyle(Brand.inkMuted)
                    Text("·")
                        .foregroundStyle(Brand.inkMuted)
                    Text(String(format: "$%.2f", item.lineTotal))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.red)
                        .monospacedDigit()
                }
            }

            Spacer()

            HStack(spacing: 0) {
                QtyButton(symbol: "minus") {
                    cart.setQuantity(productID: item.product.id, quantity: item.quantity - 1)
                }
                Text("\(item.quantity)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 28)
                QtyButton(symbol: "plus", disabled: item.quantity >= item.product.maxCartQuantity) {
                    cart.setQuantity(productID: item.product.id, quantity: item.quantity + 1)
                }
            }
            .background(Brand.surface)
            .clipShape(Capsule())
        }
        .padding(.vertical, 4)
        .navigationDestination(for: Product.self) { ProductDetailView(product: $0) }
    }
}

/// Same rule and wording as the website's cart: free standard US shipping at the threshold.
struct FreeShippingProgress: View {
    let subtotal: Double

    private var remaining: Double { max(0, Double(StoreConfig.freeShippingThreshold) - subtotal) }
    private var progress: Double { min(1, subtotal / Double(StoreConfig.freeShippingThreshold)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: remaining > 0 ? "shippingbox" : "checkmark.seal.fill")
                    .foregroundStyle(remaining > 0 ? Brand.inkMuted : Brand.success)
                if remaining > 0 {
                    Text("Add \(Text(String(format: "$%.2f", remaining)).fontWeight(.semibold).foregroundColor(Brand.ink)) for free standard US shipping (orders $\(StoreConfig.freeShippingThreshold)+)")
                } else {
                    Text("You've unlocked free standard US shipping")
                        .fontWeight(.semibold)
                        .foregroundStyle(Brand.success)
                }
            }
            .font(.footnote)
            .foregroundStyle(Brand.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: progress)
                .tint(remaining > 0 ? Brand.red : Brand.success)
                .animation(.easeOut(duration: 0.2), value: progress)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("freeShippingProgress")
    }
}

private struct QtyButton: View {
    let symbol: String
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Brand.inkMuted.opacity(0.4) : Brand.ink)
        .disabled(disabled)
    }
}
