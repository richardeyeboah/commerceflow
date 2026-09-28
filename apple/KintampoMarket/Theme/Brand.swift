import SwiftUI

enum Brand {
    static let red = Color(hex: 0xCE1126)
    static let redDark = Color(hex: 0xAD0E20)
    static let gold = Color(hex: 0xF59E0B)
    static let surface = Color(hex: 0xFAFAF9)
    static let card = Color.white
    static let ink = Color(hex: 0x1C1917)
    static let inkMuted = Color(hex: 0x57534E)
    static let line = Color(hex: 0xE7E5E4)
    static let success = Color(hex: 0x15803D)

    static let cardRadius: CGFloat = 12
    static let cardShadow = Color.black.opacity(0.06)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// Shared card chrome — one soft shadow, consistent radius.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Brand.card)
            .clipShape(RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous))
            .shadow(color: Brand.cardShadow, radius: 4, y: 1)
    }
}

extension View {
    func brandCard(padding: CGFloat = 12) -> some View { modifier(CardStyle(padding: padding)) }
}

/// Primary CTA — brand red, 48pt tall, full width.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(configuration.isPressed ? Brand.redDark : Brand.red)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(Brand.card)
            .foregroundStyle(Brand.ink)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Brand.line))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct Pill: View {
    let text: String
    var tint: Color = Brand.ink
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.9))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionLabel = "See all"
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.ink)
            Spacer()
            if let action {
                Button(actionLabel, action: action)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Brand.red)
            }
        }
    }
}
