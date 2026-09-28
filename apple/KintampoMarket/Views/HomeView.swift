import SwiftUI

struct HomeView: View {
    @Bindable private var catalog = CatalogStore.shared
    @Bindable private var recent = RecentlyViewedStore.shared
    @Bindable private var cart = CartStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !AppConfig.isConfigured {
                    ConfigBanner().padding(.horizontal)
                }

                utilityStrip

                categories

                newArrivals

                if !recent.products.isEmpty {
                    recentlyViewed
                }

                quickLinks

                StoreInfoCard().padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Brand.surface.ignoresSafeArea())
        .navigationTitle("Home")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    AppRouter.shared.requestedTab = 1
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
            }
        }
        .refreshable { await catalog.reload() }
        .navigationDestination(for: Product.self) { ProductDetailView(product: $0) }
        .navigationDestination(for: String.self) { ShopView(initialCategory: $0) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(StoreConfig.shortName)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Brand.ink)
            Text(StoreConfig.tagline)
                .font(.subheadline)
                .foregroundStyle(Brand.inkMuted)
        }
        .padding(.horizontal)
    }

    private var utilityStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                UtilityChip(icon: "bag.fill", text: "\(catalog.products.filter(\.effectiveInStock).count) in stock")
                UtilityChip(icon: "mappin.and.ellipse", text: "Free pickup · Columbus")
                UtilityChip(icon: "shippingbox.fill", text: "Ships in 24h")
                UtilityChip(icon: "lock.fill", text: "Secure checkout")
            }
            .padding(.horizontal)
        }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Shop by category").padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StoreConfig.productCategories, id: \.self) { cat in
                        NavigationLink(value: cat) {
                            Text(cat)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Brand.ink)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 40)
                                .background(Brand.card)
                                .overlay(Capsule().stroke(Brand.line))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var newArrivals: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "New arrivals").padding(.horizontal)

            if catalog.isLoading && catalog.products.isEmpty {
                SkeletonGrid().padding(.horizontal)
            } else if let errorMessage = catalog.errorMessage, catalog.products.isEmpty {
                VStack(spacing: 10) {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(Brand.inkMuted)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await catalog.reload() } }
                        .buttonStyle(SecondaryButtonStyle())
                        .frame(maxWidth: 160)
                }
                .frame(maxWidth: .infinity)
                .brandCard(padding: 20)
                .padding(.horizontal)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(catalog.featured(limit: 12)) { product in
                        NavigationLink(value: product) {
                            ProductCard(product: product)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var recentlyViewed: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recently viewed").padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recent.products.prefix(8)) { product in
                        NavigationLink(value: product) {
                            ProductCard(product: product, compact: true, showQuickAdd: false)
                                .frame(width: 140)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var quickLinks: some View {
        VStack(spacing: 8) {
            NavigationLink { BundlesView() } label: {
                QuickLinkRow(icon: "shippingbox.fill", title: "Bundles", subtitle: "Save on curated sets")
            }
            .buttonStyle(.plain)
            NavigationLink { RecipesView() } label: {
                QuickLinkRow(icon: "fork.knife", title: "Recipes", subtitle: "Shop ingredients in one tap")
            }
            .buttonStyle(.plain)
            NavigationLink { TrackOrderView() } label: {
                QuickLinkRow(icon: "location.fill", title: "Track an order", subtitle: "Pickup and shipping status")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }
}

private struct UtilityChip: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(Brand.red)
            Text(text).font(.caption.weight(.medium)).foregroundStyle(Brand.ink)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(Brand.card)
        .overlay(Capsule().stroke(Brand.line))
        .clipShape(Capsule())
    }
}

private struct QuickLinkRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Brand.red)
                .frame(width: 36, height: 36)
                .background(Brand.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                Text(subtitle).font(.caption).foregroundStyle(Brand.inkMuted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Brand.inkMuted)
        }
        .frame(minHeight: 44)
        .brandCard()
    }
}

private struct StoreInfoCard: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Store")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.ink)
            Label(StoreConfig.address, systemImage: "mappin.and.ellipse")
            Label(StoreConfig.hours, systemImage: "clock.fill")
            Button {
                let digits = StoreConfig.phone.filter(\.isNumber)
                if let url = URL(string: "tel://\(digits)") { openURL(url) }
            } label: {
                Label(StoreConfig.phone, systemImage: "phone.fill")
                    .foregroundStyle(Brand.red)
            }
            .buttonStyle(.plain)
            .frame(minHeight: 32)
        }
        .font(.caption)
        .foregroundStyle(Brand.inkMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard(padding: 14)
    }
}

private struct ConfigBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.gold)
            Text("Missing Supabase keys in Config.xcconfig.")
                .font(.caption)
        }
        .padding(12)
        .background(Brand.gold.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
