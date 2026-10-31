import SwiftUI
import AuthenticationServices
import CryptoKit

/// "Continue with Apple / Google". Each button appears only when that provider is switched on
/// in Supabase (Authentication → Providers), so customers never see a button that cannot work.
struct SocialSignInButtons: View {
    var onSignedIn: () -> Void = {}

    @Bindable private var auth = AuthStore.shared
    private var providers: Set<String> { auth.socialProviders }
    @State private var nonce = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.colorScheme) private var colorScheme

    /// Must also be listed under Supabase → Authentication → URL Configuration → Redirect URLs.
    static let callbackScheme = "kintampo"
    static let callbackURL = "kintampo://auth-callback"

    var body: some View {
        VStack(spacing: 10) {
            if providers.contains("apple") {
                SignInWithAppleButton(.continue) { request in
                    nonce = Self.randomString(length: 32)
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = Self.sha256Hex(nonce)
                } onCompletion: { result in
                    Task { await finishApple(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(busy)
                .accessibilityIdentifier("signInWithApple")
            }
            if providers.contains("google") {
                Button {
                    Task { await signInWithGoogle() }
                } label: {
                    HStack(spacing: 10) {
                        GoogleMark().frame(width: 18, height: 18)
                        Text("Continue with Google")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(Brand.ink)
                    .background(Brand.card)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Brand.line, lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityIdentifier("signInWithGoogle")
            }
            if busy {
                ProgressView()
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if providers.contains("apple") || providers.contains("google") {
                HStack(spacing: 10) {
                    VStack { Divider() }
                    Text("or use email").font(.caption).foregroundStyle(Brand.inkMuted).fixedSize()
                    VStack { Divider() }
                }
                .padding(.top, 4)
            }
        }
        .task { await auth.loadSocialProviders() }
    }

    private func finishApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "Apple sign-in failed. Please try again."
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Apple did not return a sign-in token."
                return
            }
            let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            busy = true
            defer { busy = false }
            do {
                try await AuthStore.shared.signInWithApple(idToken: idToken, nonce: nonce, fullName: name)
                errorMessage = nil
                onSignedIn()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func signInWithGoogle() async {
        let verifier = Self.randomString(length: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let url = SupabaseService.shared.oauthAuthorizeURL(
            provider: "google", redirectTo: Self.callbackURL, codeChallenge: challenge
        )
        busy = true
        defer { busy = false }
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: url, callbackURLScheme: Self.callbackScheme
            )
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard let code = items.first(where: { $0.name == "code" })?.value else {
                let reason = items.first(where: { $0.name == "error_description" })?.value
                errorMessage = reason ?? "Google sign-in was not completed."
                return
            }
            try await AuthStore.shared.signInWithOAuthCode(code, verifier: verifier)
            errorMessage = nil
            onSignedIn()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Customer closed the sheet.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// URL-safe random string (also valid as a PKCE verifier: unreserved characters only).
    static func randomString(length: Int) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Google "G" drawn in its four brand colors, so no image asset is needed.
private struct GoogleMark: View {
    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height)
            let line = w * 0.2
            let center = CGPoint(x: w / 2, y: w / 2)
            let radius = (w - line) / 2
            ZStack {
                arc(center, radius, from: -40, to: 45, color: Color(hex: 0x4285F4), line: line)
                arc(center, radius, from: 45, to: 135, color: Color(hex: 0x34A853), line: line)
                arc(center, radius, from: 135, to: 210, color: Color(hex: 0xFBBC05), line: line)
                arc(center, radius, from: 210, to: 320, color: Color(hex: 0xEA4335), line: line)
                Rectangle()
                    .fill(Color(hex: 0x4285F4))
                    .frame(width: w / 2, height: line)
                    .position(x: w * 0.75, y: w / 2)
            }
        }
        .accessibilityHidden(true)
    }

    private func arc(_ c: CGPoint, _ r: CGFloat, from: Double, to: Double, color: Color, line: CGFloat) -> some View {
        Path { p in
            p.addArc(center: c, radius: r, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
        }
        .stroke(color, lineWidth: line)
    }
}
