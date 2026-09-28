import SwiftUI

struct ShopView: View {
    var initialCategory: String? = nil

    @Bindable private var catalog = CatalogStore.shared
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var inStockOnly = false
    @State private var sort: CatalogSort = .newest
    @State private var remoteResults: [Product]?
    @State private var searching = false
    @FocusState private var searchFocused: Bool

    private var visible: [Product] {
        if let remoteResults {
            return applyLocalFilters(remoteResults)
        }
        return catalog.filtered(search: searchText, category: selectedCategory, inStockOnly: inStockOnly, sort: sort)
    }

    private func applyLocalFilters(_ list: [Product]) -> [Product] {
        var filtered = list
        if let selectedCategory, !selectedCategory.isEmpty {
            filtered = filtered.filter { $0.category == selectedCategory }
        }
        if inStockOnly { filtered = filtered.filter(\.effectiveInStock) }
        return sort.apply(filtered)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryChip(title: "All", selected: selectedCategory == nil) { selectedCategory = nil }
                    ForEach(StoreConfig.productCategories, id: \.self) { cat in
                        CategoryChip(title: cat, selected: selectedCategory == cat) {
                            selectedCategory = selectedCategory == cat ? nil : cat
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }

            HStack(spacing: 10) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(CatalogSort.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sort.label)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(Brand.card)
                    .overlay(Capsule().stroke(Brand.line))
                    .clipShape(Capsule())
                }

                Toggle(isOn: $inStockOnly) {
                    Text("In stock")
                        .font(.caption.weight(.semibold))
                }
                .toggleStyle(.button)
                .tint(Brand.red)
                .controlSize(.small)

                Spacer()

                Text("\(visible.count) items")
                    .font(.caption)
                    .foregroundStyle(Brand.inkMuted)
                    .monospacedDigit()
            }
            .padding(.horizontal)
            .padding(.bottom, 10)

            Group {
                if (catalog.isLoading && catalog.products.isEmpty) || searching {
                    ScrollView { SkeletonGrid().padding() }
                } else if let error = catalog.errorMessage, catalog.products.isEmpty {
                    ContentUnavailableView {
                        Label("Could not load", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await catalog.reload() } }
                            .buttonStyle(SecondaryButtonStyle())
                            .frame(maxWidth: 160)
                    }
                } else if visible.isEmpty {
                    ContentUnavailableView {
                        Label("No products", systemImage: "bag")
                    } description: {
                        Text(searchText.isEmpty ? "Try another category." : "No match for “\(searchText)”.")
                    } actions: {
                        if !searchText.isEmpty || selectedCategory != nil || inStockOnly {
                            Button("Clear filters") {
                                searchText = ""
                                selectedCategory = nil
                                inStockOnly = false
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .frame(maxWidth: 160)
                        }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(visible) { product in
                                NavigationLink(value: product) {
                                    ProductCard(product: product)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
            }
        }
        .background(Brand.surface.ignoresSafeArea())
        .navigationTitle("Shop")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(for: Product.self) { ProductDetailView(product: $0) }
        .navigationDestination(for: String.self) { id in ProductByIDView(productID: id) }
        .task {
            if let initialCategory { selectedCategory = initialCategory }
            await catalog.loadIfNeeded()
        }
        .refreshable { await catalog.reload() }
        .task(id: searchText) { await runServerSearch() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Brand.inkMuted)
            TextField("Search products", text: $searchText)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($searchFocused)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.inkMuted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Brand.card)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(searchFocused ? Brand.red : Brand.line))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.vertical, 10)
        .animation(.easeOut(duration: 0.12), value: searchFocused)
    }

    private func runServerSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            remoteResults = nil
            searching = false
            return
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        searching = catalog.filtered(search: query).isEmpty
        let found = try? await SupabaseService.shared.searchAllProducts(query: query)
        guard !Task.isCancelled, searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
        searching = false
        // Merge server hits with local matches so nothing already cached disappears.
        let local = catalog.filtered(search: query)
        var merged = local
        let seen = Set(local.map(\.id))
        for p in found ?? [] where !seen.contains(p.id) { merged.append(p) }
        remoteResults = merged
    }
}

struct ProductByIDView: View {
    let productID: String
    @State private var product: Product?
    @State private var failed = false

    var body: some View {
        Group {
            if let product {
                ProductDetailView(product: product)
            } else if failed {
                ContentUnavailableView("Product not found", systemImage: "bag", description: Text("It may have been removed."))
            } else {
                ProgressView()
            }
        }
        .task {
            product = try? await SupabaseService.shared.fetchProduct(id: productID)
            failed = product == nil
        }
    }
}

private struct CategoryChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(selected ? Brand.red : Brand.card)
                .foregroundStyle(selected ? .white : Brand.ink)
                .overlay(Capsule().stroke(selected ? Brand.red : Brand.line))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}
