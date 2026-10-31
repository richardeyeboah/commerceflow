import SwiftUI

struct ProductCard: View {
    let product: Product
    var compact = false
    var showQuickAdd = true
    @State private var justAdded = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var lowStock: Int? {
        guard let qty = product.stockQuantity, qty > 0, qty <= 5 else { return nil }
        return qty
    }

    private var imageHeight: CGFloat {
        let base: CGFloat = compact ? 110 : 150
        return typeSize.isAccessibilitySize ? base * 1.4 : base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                CachedProductImage(url: product.primaryImageURL)
                    .frame(height: imageHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if !product.effectiveInStock {
                    Pill(text: "Out of stock").padding(8)
                } else if let lowStock {
                    Pill(text: "Only \(lowStock) left", tint: Brand.gold).padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                if let brand = product.brand?.trimmingCharacters(in: .whitespaces), !brand.isEmpty {
                    Text(brand.uppercased())
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(Brand.inkMuted)
                        .lineLimit(1)
                }
                Text(product.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Brand.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: compact || typeSize.isAccessibilitySize ? 0 : 38, alignment: .top)
                if let pack = product.packLabel, !pack.isEmpty {
                    Text(pack).font(.caption2).foregroundStyle(Brand.inkMuted)
                }
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(product.displayPrice)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Brand.red)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let unit = product.unitPriceLabel {
                        Text(unit).font(.caption2).foregroundStyle(Brand.inkMuted)
                    }
                }
                Spacer(minLength: 4)
                if product.effectiveInStock, showQuickAdd {
                    Button {
                        CartStore.shared.add(product, quantity: 1)
                        justAdded = true
                        Task {
                            try? await Task.sleep(nanoseconds: 900_000_000)
                            justAdded = false
                        }
                    } label: {
                        Image(systemName: justAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(justAdded ? Brand.success : Brand.red)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(justAdded ? "Added" : "Add to cart")
                    .animation(.easeOut(duration: 0.15), value: justAdded)
                }
            }
        }
        .brandCard(padding: compact ? 8 : 12)
    }
}

struct SkeletonGrid: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)).frame(height: 150)
                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12)).frame(height: 14)
                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12)).frame(width: 70, height: 14)
                }
                .brandCard()
                .redacted(reason: .placeholder)
            }
        }
    }
}

/// Placeholder list rows shown while store-manager data loads (skeletons, not spinners).
struct SkeletonRows: View {
    var count = 6
    var showsImage = true

    var body: some View {
        ForEach(0..<count, id: \.self) { _ in
            HStack(spacing: 12) {
                if showsImage {
                    RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12)).frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12)).frame(height: 12)
                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12)).frame(width: 110, height: 10)
                }
                Spacer(minLength: 24)
                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12)).frame(width: 48, height: 12)
            }
            .padding(.vertical, 4)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}
