import SwiftUI

/// iPhone / iPad / Mac — tab shell mirrors the mobile web bottom nav.
struct RootTabView: View {
    @Bindable private var cart = CartStore.shared
    @Bindable private var router = AppRouter.shared
    @State private var tab = 0
    @State private var shopPath = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)

            NavigationStack(path: $shopPath) {
                ShopView()
            }
            .tabItem { Label("Shop", systemImage: "bag.fill") }
            .tag(1)

            NavigationStack {
                CartView()
            }
            .tabItem {
                Label("Cart", systemImage: "cart.fill")
            }
            .badge(cart.itemCount > 0 ? cart.itemCount : 0)
            .tag(2)

            NavigationStack {
                TrackOrderView()
            }
            .tabItem { Label("Track", systemImage: "shippingbox.fill") }
            .tag(3)

            NavigationStack {
                AccountView()
            }
            .tabItem { Label("Account", systemImage: "person.fill") }
            .tag(4)
        }
        .tint(Brand.red)
        .onChange(of: router.pendingProductID) { _, id in
            guard let id else { return }
            tab = 1
            shopPath.append(id)
            router.pendingProductID = nil
        }
        .onChange(of: router.requestedTab) { _, next in
            guard let next else { return }
            tab = next
            router.requestedTab = nil
        }
        .safeAreaInset(edge: .top) {
            if AppConfig.fixtureURL != nil {
                Text("TEST MODE — sample products and test payments")
                    .font(.caption).frame(maxWidth: .infinity).padding(6)
                    .background(.yellow.opacity(0.2))
            }
        }
    }
}

#if os(macOS)
/// Mac uses the same tabs; optionally switch to sidebar later.
typealias PlatformRootView = RootTabView
#elseif os(iOS)
typealias PlatformRootView = RootTabView
#endif
