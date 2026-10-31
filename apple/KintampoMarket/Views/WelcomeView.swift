import SwiftUI

/// Shown once, the first time the app opens.
struct WelcomeView: View {
    var onStart: () -> Void
    var onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Image("WelcomeTextiles")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 340)
                    .clipped()
                    .accessibilityHidden(true)
                LinearGradient(colors: [.clear, Brand.forest], startPoint: .center, endPoint: .bottom)
                Image("LogoMark")
                    .resizable()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.9), lineWidth: 3))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    .offset(y: 42)
                    .accessibilityLabel("Kintampo logo")
            }
            .frame(height: 340)

            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text("AKWAABA")
                        .font(.caption.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(Brand.kenteGold)
                    Text("Welcome to Kintampo African Market")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(StoreConfig.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: 14) {
                    WelcomeRow(icon: "basket.fill", title: "Real Ghanaian & Caribbean staples",
                               detail: "Fufu, gari, yam, spices, drinks, prints and beauty.")
                    WelcomeRow(icon: "storefront.fill", title: "Free pickup in Columbus",
                               detail: "Order ahead and collect from the store.")
                    WelcomeRow(icon: "shippingbox.fill", title: "Ships nationwide",
                               detail: "Free shipping on orders over $\(StoreConfig.freeShippingThreshold).")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button("Start shopping", action: onStart)
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("welcomeStart")
                    Button("I already have an account", action: onSignIn)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 12)
        }
        .background(Brand.forest.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
    }
}

private struct WelcomeRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Brand.forest)
                .frame(width: 38, height: 38)
                .background(Brand.kenteGold)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.75))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
