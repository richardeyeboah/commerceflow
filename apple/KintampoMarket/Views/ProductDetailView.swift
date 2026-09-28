import SwiftUI

struct ProductDetailView: View {
    let product: Product
    @State private var detail: Product
    @State private var quantity = 1
    @State private var added = false
    @State private var isLoadingDetail = false
    @State private var selectedImageIndex = 0
    @State private var variants: [Product] = []
    @State private var related: [Product] = []
    @Bindable private var wishlist = WishlistStore.shared
    @Bindable private var auth = AuthStore.shared
    @Bindable private var cart = CartStore.shared

    init(product: Product) {
        self.product = product
        _detail = State(initialValue: product)
    }

    private var galleryURLs: [URL] {
        var urls: [URL] = []
        if let main = detail.primaryImageURL { urls.append(main) }
        for raw in detail.imageURLs ?? [] {
            guard let url = URL(string: raw), !urls.contains(url) else { continue }
            urls.append(url)
        }
        return urls
    }

    private var maxQty: Int { max(1, detail.maxCartQuantity == 0 ? 1 : detail.maxCartQuantity) }
    private var inCart: Int { cart.items.first { $0.product.id == detail.id }?.quantity ?? 0 }
    private var lowStock: Int? {
        guard let qty = detail.stockQuantity, qty > 0, qty <= 5 else { return nil }
        return qty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                gallery

                VStack(alignment: .leading, spacing: 10) {
                    Text(detail.category.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Brand.red)

                    HStack(alignment: .top) {
                        Text(detail.name)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Brand.ink)
                        Spacer(minLength: 8)
                        HStack(spacing: 4) {
                            ShareLink(
                                item: StorefrontCatalog.publicProductURL(id: detail.id),
                                subject: Text(detail.name),
                                message: Text("\(detail.name) — order at Kintampo African Market")
                            ) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Brand.ink)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)

                            if auth.isSignedIn {
                                Button {
                                    Task { await wishlist.toggle(detail) }
                                } label: {
                                    Image(systemName: wishlist.contains(detail.id) ? "heart.fill" : "heart")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Brand.red)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(wishlist.contains(detail.id) ? "Remove from wishlist" : "Save to wishlist")
                            }
                        }
                    }

                    if let brand = detail.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
                        Text(brand)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.inkMuted)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(detail.displayPrice)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Brand.ink)
                            .monospacedDigit()
                        if let pack = detail.packLabel, !pack.isEmpty {
                            Text(pack).font(.subheadline).foregroundStyle(Brand.inkMuted)
                        }
                        if let unit = detail.unitPriceLabel {
                            Text(unit).font(.caption).foregroundStyle(Brand.inkMuted)
                        }
                    }

                    HStack(spacing: 8) {
                        if !detail.effectiveInStock {
                            StatusChip(text: "Out of stock", color: Brand.inkMuted)
                        } else if let lowStock {
                            StatusChip(text: "Only \(lowStock) left", color: Brand.gold)
                        } else {
                            StatusChip(text: "In stock", color: Brand.success)
                        }
                        StatusChip(text: "Free pickup", color: Brand.inkMuted, filled: false)
                    }

                    if let tags = detail.dietaryTags?.filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }), !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(tags, id: \.self) { tag in
                                    StatusChip(text: tag, color: Brand.inkMuted, filled: false)
                                }
                            }
                        }
                    }
                }

                if variants.count > 1 {
                    variantPicker
                }

                purchaseBlock

                if isLoadingDetail, detail.description == nil {
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                } else if let description = detail.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("About this product")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.ink)
                        Text(description)
                            .font(.body)
                            .foregroundStyle(Brand.inkMuted)
                    }
                }

                ProductReviewsSection(productID: detail.id)
                    .id(detail.id)

                if !related.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "More in \(detail.category)")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(related) { item in
                                    NavigationLink(value: item) {
                                        ProductCard(product: item, compact: true)
                                            .frame(width: 150)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Brand.surface.ignoresSafeArea())
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { RecentlyViewedStore.shared.record(detail) }
        .task(id: detail.id) {
            if auth.isSignedIn { await wishlist.refresh() }
            await loadFullProduct()
        }
        .onChange(of: added) { _, value in
            guard value else { return }
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                added = false
            }
        }
    }

    private var variantPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Size")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(variants.sorted { ($0.unitAmount ?? $0.price) < ($1.unitAmount ?? $1.price) }) { variant in
                        let active = variant.id == detail.id
                        Button {
                            detail = variant
                            quantity = 1
                            selectedImageIndex = 0
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(variant.packLabel?.isEmpty == false ? variant.packLabel! : variant.displayPrice)
                                    .font(.subheadline.weight(.semibold))
                                Text(variant.effectiveInStock ? variant.displayPrice : "Out")
                                    .font(.caption)
                                    .opacity(0.8)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .background(active ? Brand.ink : Brand.card)
                            .foregroundStyle(active ? Color.white : (variant.effectiveInStock ? Brand.ink : Brand.inkMuted))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(active ? Brand.ink : Brand.line))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var purchaseBlock: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Quantity")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Brand.ink)
                Spacer()
                HStack(spacing: 0) {
                    Button { quantity = max(1, quantity - 1) } label: {
                        Image(systemName: "minus").font(.caption.weight(.bold)).frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .disabled(quantity <= 1)
                    Text("\(quantity)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(minWidth: 32)
                    Button { quantity = min(maxQty, quantity + 1) } label: {
                        Image(systemName: "plus").font(.caption.weight(.bold)).frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .disabled(quantity >= maxQty)
                }
                .foregroundStyle(Brand.ink)
                .background(Brand.surface)
                .clipShape(Capsule())
                .disabled(!detail.effectiveInStock)
            }

            Button {
                CartStore.shared.add(detail, quantity: quantity)
                added = true
            } label: {
                HStack {
                    Image(systemName: added ? "checkmark" : "cart.badge.plus")
                    Text(added ? "Added to cart" : (detail.effectiveInStock ? "Add to cart" : "Out of stock"))
                    Spacer()
                    Text(String(format: "$%.2f", detail.price * Double(quantity))).monospacedDigit()
                }
                .padding(.horizontal, 16)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!detail.effectiveInStock)
            .accessibilityIdentifier("addToCart")

            if inCart > 0 {
                HStack {
                    Text("\(inCart) in cart")
                        .font(.caption)
                        .foregroundStyle(Brand.inkMuted)
                    Spacer()
                    Button("View cart") { AppRouter.shared.requestedTab = 2 }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.red)
                }
            }
        }
        .brandCard(padding: 14)
    }

    @ViewBuilder
    private var gallery: some View {
        let urls = galleryURLs
        if urls.isEmpty {
            CachedProductImage(url: nil)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous))
        } else {
            VStack(spacing: 8) {
                TabView(selection: $selectedImageIndex) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        CachedProductImage(url: url)
                            .frame(height: 300)
                            .clipped()
                            .tag(index)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
                #endif
                .frame(height: 300)
                .background(Brand.card)
                .clipShape(RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous))

                if urls.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                                Button { selectedImageIndex = index } label: {
                                    CachedProductImage(url: url)
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(index == selectedImageIndex ? Brand.red : Brand.line, lineWidth: index == selectedImageIndex ? 2 : 1)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadFullProduct() async {
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            if let full = try await SupabaseService.shared.fetchProduct(id: detail.id),
               !StorefrontCatalog.isHidden(full)
            {
                detail = full
                RecentlyViewedStore.shared.record(full)
            }
            if let group = detail.variantGroup, !group.isEmpty {
                variants = (try? await SupabaseService.shared.fetchVariants(group: group)) ?? []
            } else {
                variants = []
            }
            related = (try? await SupabaseService.shared.fetchRelated(category: detail.category, excludeID: detail.id)) ?? []
        } catch {
            // Keep list payload; detail fields stay optional.
        }
    }
}

private struct StatusChip: View {
    let text: String
    let color: Color
    var filled = true
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .background(filled ? color.opacity(0.12) : Color.clear)
            .foregroundStyle(filled ? color : Brand.inkMuted)
            .overlay(Capsule().stroke(filled ? Color.clear : Brand.line))
            .clipShape(Capsule())
    }
}
