#if os(iOS)
import SwiftUI
import StripePaymentSheet
import PassKit

struct NativePaymentView: View {
    let payment: PaymentIntentResult
    let onComplete: (String) -> Void
    @State private var sheet: PaymentSheet?
    @State private var message = "Pay with a card. Encrypted by Stripe."
    @State private var paymentSubmitted = false
    @State private var checking = false
    @State private var pollAttempt = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("Kintampo African Market")
                .font(.headline)
                .foregroundStyle(Brand.ink)
            Group {
                LabeledContent("Subtotal", value: money(payment.subtotal))
                LabeledContent("Delivery / shipping", value: money(payment.shippingFee))
                LabeledContent("Tax", value: money(payment.taxAmount))
                LabeledContent("Total", value: money(payment.total))
                    .font(.headline)
                    .foregroundStyle(Brand.ink)
            }
            .monospacedDigit()

            if let sheet, !paymentSubmitted {
                PaymentSheet.PaymentButton(paymentSheet: sheet, onCompletion: handleResult) {
                    Text("Pay \(money(payment.total))")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.red)
                .accessibilityIdentifier("payButton")
            }

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("paymentStatus")

            if paymentSubmitted {
                Button(checking ? "Confirming order…" : "Check payment status") {
                    Task { await confirmOrder(autoRetry: false) }
                }
                .disabled(checking)
            }

            Spacer()
        }
        .padding()
        .background(Brand.surface.ignoresSafeArea())
        .navigationTitle("Payment")
        .navigationBarTitleDisplayMode(.inline)
        .task { configureSheet() }
    }

    private func money(_ amount: Double) -> String { String(format: "$%.2f", amount) }

    private func configureSheet() {
        STPAPIClient.shared.publishableKey = payment.publishableKey ?? AppConfig.stripePublishableKey
        var config = PaymentSheet.Configuration()
        config.merchantDisplayName = "Kintampo African Market"
        config.returnURL = "kintampo://stripe-redirect"
        config.allowsDelayedPaymentMethods = false
        let merchantId = AppConfig.applePayMerchantId
        if !merchantId.isEmpty, PKPaymentAuthorizationController.canMakePayments() {
            config.applePay = .init(
                merchantId: merchantId,
                merchantCountryCode: "US"
            )
        }
        sheet = PaymentSheet(paymentIntentClientSecret: payment.clientSecret, configuration: config)
    }

    private func handleResult(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            paymentSubmitted = true
            message = "Payment received. Confirming your order…"
            Task { await confirmOrder(autoRetry: true) }
        case .canceled:
            message = "Payment canceled. Your cart is still saved."
        case .failed(let error):
            message = error.localizedDescription
        }
    }

    private func confirmOrder(autoRetry: Bool) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }

        let maxAttempts = autoRetry ? 5 : 1
        for attempt in 1...maxAttempts {
            pollAttempt = attempt
            do {
                let token = try await AuthStore.shared.validAccessToken()
                let result = try await APIClient.shared.checkoutStatus(
                    paymentIntentId: payment.intentID,
                    accessToken: token
                )
                if let confirmation = result.confirmationMessage {
                    onComplete(confirmation)
                    return
                }
                message = "Payment went through. Order confirmation is still processing…"
            } catch {
                message = "Could not confirm yet. Tap Check payment status — do not pay twice."
            }
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 700_000_000)
            }
        }
        if autoRetry {
            message = "Payment may have succeeded. Tap Check payment status before paying again."
        }
    }
}
#endif
