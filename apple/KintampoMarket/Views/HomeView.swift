import SwiftUI

struct HomeView: View {
    @Bindable private var catalog = CatalogStore.shared
    @Bindable private var recent = RecentlyViewedStore.shared
    @Bindable private var cart = CartStore.shared
    @State private var announcements: [Announcement] = Announcement.fallback
    @State private var bestsellers: [Product] = []
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AnnouncementTicker(items: announcements) { open($0) }
                    .padding(.horizontal)

                WelcomeHero(inStock: catalog.products.filter(\.effectiveInStock).count)
                    .padding(.horizontal)

                if !AppConfig.isConfigured {
                    ConfigBanner().padding(.horizontal)
                }

                utilityStrip

                categories

                if !bestsellers.isEmpty {
                    productShelf("Bestsellers", subtitle: "Most ordered by our customers", products: bestsellers)
                }

                productShelf("Yam, fufu & staples", subtitle: "Plantain, fufu, yam and pantry essentials", products: staples)

                WhatsAppCard().padding(.horizontal)

                productShelf("Trending this week", subtitle: "Popular across the store", products: trending)

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
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image("LogoMark")
                        .resizable()
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("Kintampo")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Brand.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Kintampo African Market")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    AppRouter.shared.requestedTab = 1
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
            }
        }
        .refreshable {
            await catalog.reload()
            await loadMerchandising()
        }
        .task { await loadMerchandising() }
        .navigationDestination(for: Product.self) { ProductDetailView(product: $0) }
        .navigationDestination(for: String.self) { ShopView(initialCategory: $0) }
    }

    private var utilityStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                UtilityChip(icon: "mappin.and.ellipse", text: "Free pickup · Columbus")
                UtilityChip(icon: "shippingbox.fill", text: "Free shipping $\(StoreConfig.freeShippingThreshold)+")
                UtilityChip(icon: "clock.fill", text: "Ships in 24h")
                UtilityChip(icon: "lock.fill", text: "Secure checkout")
            }
            .padding(.horizontal)
        }
    }

    private var staples: [Product] { HomeMerchandising.staples(from: catalog.products) }

    private var trending: [Product] {
        let shown = Set((staples + bestsellers).map(\.id))
        return HomeMerchandising.trending(from: catalog.products, excluding: shown)
    }

    private func loadMerchandising() async {
        if let rows = try? await SupabaseService.shared.fetchAnnouncements(), !rows.isEmpty {
            announcements = rows
        }
        bestsellers = StorefrontCatalog.visible(await APIClient.shared.bestsellers())
    }

    /// Product links stay in the app; anything else opens the website page.
    private func open(_ href: String) {
        let url = href.hasPrefix("http") ? URL(string: href) : URL(string: href, relativeTo: AppConfig.siteURL)?.absoluteURL
        guard let url else { return }
        if AppRouter.productID(from: url) != nil { AppRouter.shared.open(url) } else { openURL(url) }
    }

    @ViewBuilder
    private func productShelf(_ title: String, subtitle: String, products: [Product]) -> some View {
        if !products.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionHeader(title: title)
                    Text(subtitle).font(.caption).foregroundStyle(Brand.inkMuted)
                }
                .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(products) { product in
                            NavigationLink(value: product) {
                                ProductCard(product: product, compact: true)
                                    .frame(width: 150)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    /// Departments that actually have stock, biggest first — mirrors the website's department grid.
    private var departments: [(name: String, count: Int)] {
        let counts = Dictionary(grouping: catalog.products.filter(\.effectiveInStock), by: \.category)
            .mapValues(\.count)
        return counts.filter { !$0.key.isEmpty }
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Shop by department", action: { AppRouter.shared.requestedTab = 1 }).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.fixed(118), spacing: 10), GridItem(.fixed(118), spacing: 10)], spacing: 10) {
                    ForEach(departments, id: \.name) { dept in
                        NavigationLink(value: dept.name) {
                            DepartmentTile(
                                name: dept.name,
                                count: dept.count,
                                imageURL: StoreConfig.categoryImageURL(dept.name)
                                    ?? catalog.products.first { $0.category == dept.name && $0.primaryImageURL != nil }?.primaryImageURL
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 246)
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

/// Rotating strip of the website's admin-managed announcements.
private struct AnnouncementTicker: View {
    let items: [Announcement]
    let onOpen: (String) -> Void
    @State private var index = 0

    var body: some View {
        if let item = items.isEmpty ? nil : items[index % items.count] {
            Button {
                if let href = item.href, !href.isEmpty { onOpen(href) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "megaphone.fill").font(.caption).foregroundStyle(Brand.kenteGold)
                    Text(item.message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .id(item.id)
                        .transition(.push(from: .bottom))
                    Spacer(minLength: 0)
                    if item.href?.isEmpty == false {
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Brand.forest)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipped()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.message)
            .task(id: items.count) {
                guard items.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation(.easeInOut(duration: 0.35)) { index += 1 }
                }
            }
        }
    }
}

/// WhatsApp is how many customers already order from the store.
private struct WhatsAppCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = StoreConfig.whatsAppURL(message: "Hi Kintampo! I'd like to place an order / ask a question.") {
                openURL(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "message.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: 0x25D366))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Order or ask on WhatsApp").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                    Text("Can't find something? Message the store.").font(.caption).foregroundStyle(Brand.inkMuted)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(Brand.inkMuted)
            }
            .brandCard(padding: 12)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens WhatsApp")
    }
}

/// Welcome banner at the top of Home: store photo, greeting, and the two main ways in.
private struct WelcomeHero: View {
    let inStock: Int
    @Bindable private var auth = AuthStore.shared

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        let first = auth.profile?.fullName?.split(separator: " ").first.map(String.init)
        return first.map { "\(part), \($0)" } ?? "Akwaaba — welcome"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image("WelcomeHero")
                .resizable()
                .scaledToFill()
                .frame(height: 340)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityHidden(true)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Brand.forest.opacity(0.55), location: 0.35),
                    .init(color: Brand.forest.opacity(0.97), location: 0.75),
                ],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 10) {
                Text(greeting.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Brand.kenteGold)
                Text("Ghana & Caribbean groceries — in stock now.")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(inStock > 0
                     ? "\(inStock) products · Pickup in Columbus or ships nationwide."
                     : "Pickup in Columbus or ships nationwide.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                HStack(spacing: 10) {
                    Button { AppRouter.shared.requestedTab = 1 } label: {
                        Label("Shop all", systemImage: "arrow.right")
                            .labelStyle(TrailingIconLabelStyle())
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 42)
                            .background(Brand.red)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    NavigationLink(value: StoreConfig.fashionGroup) {
                        Text("Shop fashion")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 42)
                            .background(.white.opacity(0.95))
                            .foregroundStyle(Brand.ink)
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(18)
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Brand.cardShadow, radius: 10, y: 4)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

private struct DepartmentTile: View {
    let name: String
    let count: Int
    let imageURL: URL?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedProductImage(url: imageURL)
                .frame(width: 150, height: 118)
                .clipped()
            LinearGradient(
                stops: [.init(color: .clear, location: 0.3), .init(color: .black.opacity(0.8), location: 1)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                Text("\(count) item\(count == 1 ? "" : "s")")
                    .font(.caption2)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(10)
        }
        .frame(width: 150, height: 118)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
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
