import Foundation
import Observation

/// Store-manager client for `/api/admin/*`.
/// Auth is the same signed `admin_session` cookie the web dashboard uses; URLSession keeps it
/// in the shared cookie store. State-changing calls send `Origin` to pass `assertSameOrigin`.
struct AdminAPI {
    static let shared = AdminAPI()
    var session: URLSession = .shared
    var baseURL: URL = AppConfig.siteURL

    func login(password: String) async throws {
        var request = jsonRequest(path: "api/admin/login", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["password": password])
        _ = try await send(request)
    }

    func logout() async throws {
        _ = try await send(jsonRequest(path: "api/admin/logout", method: "POST"))
    }

    func orders(queue: AdminQueue, status: String?, search: String) async throws -> [AdminOrder] {
        var components = URLComponents(url: baseURL.appending(path: "api/admin/orders"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "queue", value: queue.rawValue)]
        if let status { items.append(URLQueryItem(name: "status", value: status)) }
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty { items.append(URLQueryItem(name: "q", value: term)) }
        components.queryItems = items
        let data = try await send(URLRequest(url: components.url!))
        struct Response: Decodable { let orders: [AdminOrder] }
        return try JSONDecoder().decode(Response.self, from: data).orders
    }

    func order(id: String) async throws -> AdminOrderDetail {
        let data = try await send(URLRequest(url: baseURL.appending(path: "api/admin/orders/\(id)")))
        return try JSONDecoder().decode(AdminOrderDetail.self, from: data)
    }

    func updateStatus(orderID: String, status: String, trackingNumber: String, note: String) async throws {
        var request = jsonRequest(path: "api/admin/orders/\(orderID)", method: "PATCH")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "status": status,
            "trackingNumber": trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            "note": note.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
        _ = try await send(request)
    }

    private func jsonRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.network("No response") }
        if http.statusCode == 401 || http.statusCode == 403 { throw AppError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw AppError.network(message ?? "Request failed (\(http.statusCode))")
        }
        return data
    }
}

@Observable
@MainActor
final class AdminStore {
    static let shared = AdminStore()

    var isSignedIn = false
    var checked = false

    /// A stored cookie may still be valid from an earlier launch; probe once.
    func restore() async {
        guard !checked else { return }
        do {
            _ = try await AdminAPI.shared.orders(queue: .needsAction, status: nil, search: "")
            isSignedIn = true
        } catch {
            isSignedIn = false
        }
        checked = true
    }

    func signIn(password: String) async throws {
        try await AdminAPI.shared.login(password: password)
        isSignedIn = true
        checked = true
    }

    func signOut() async {
        try? await AdminAPI.shared.logout()
        isSignedIn = false
    }

    /// Called when any admin request comes back 401/403.
    func sessionExpired() {
        isSignedIn = false
    }
}
