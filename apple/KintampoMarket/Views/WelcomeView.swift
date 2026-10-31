import SwiftUI

/// Shown once, the first time the app opens. Neutral surface and direct utility copy
/// (AGENTS.md: no cultural theming in chrome, surfaces stay white/warm stone).
struct WelcomeView: View {
    var onStart: () -> Void
    var onSignIn: () -> Void

    var body: some View {
        // Fits on one screen at normal sizes; scrolls when large text makes it taller.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollBounceBehavior(.basedOnSize)
        }
        .background(Brand.surface.ignoresSafeArea())
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 14) {
                Image("LogoMark")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Kintampo logo")
                Text("Kintampo African Market")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Brand.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("African & Caribbean groceries. Order on your phone, pick up in Columbus or get it shipped.")
                    .font(.body)
                    .foregroundStyle(Brand.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                WelcomeRow(icon: "checkmark.seal.fill", title: "In stock now",
                           detail: "Fufu, gari, yam, rice, spices, drinks and beauty.")
                WelcomeRow(icon: "storefront.fill", title: "Free pickup",
                           detail: StoreConfig.address)
                WelcomeRow(icon: "shippingbox.fill", title: "Free shipping $\(StoreConfig.freeShippingThreshold)+",
                           detail: "Ships nationwide within 24 hours.")
            }

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                Button("Start shopping", action: onStart)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("welcomeStart")
                Button("Sign in", action: onSignIn)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Brand.red)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
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
                .foregroundStyle(Brand.red)
                .frame(width: 40, height: 40)
                .background(Brand.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                Text(detail).font(.subheadline).foregroundStyle(Brand.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
