import Foundation

final class MockHTTP: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var handler: ((URLRequest) throws -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            Self.lock.lock()
            let result: (Int, String)
            do { result = try Self.handler(request); Self.lock.unlock() }
            catch { Self.lock.unlock(); throw error }
            let response = HTTPURLResponse(url: request.url!, statusCode: result.0, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(result.1.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main struct MobileRegression {
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        precondition(condition, message)
        checks += 1
    }
    static func decode<T: Decodable>(_ value: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(value.utf8))
    }
    static func product(_ id: String, stock: Int? = nil) throws -> Product {
        try decode("""
        {"id":"\(id)","name":"Yam","price":5,"category":"Produce","in_stock":true,"created_at":"2026-01-01","stock_quantity":\(stock.map(String.init) ?? "null")}
        """, as: Product.self)
    }
    @MainActor static func main() async throws {
        let suite = "kintampo-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cart = CartStore(defaults: defaults)
        let limited = try product("limited", stock: 2)
        cart.add(limited, quantity: 50)
        check(cart.itemCount == 2, "Stock must cap additions")
        cart.add(limited)
        check(cart.itemCount == 2, "Repeated additions must respect stock")
        cart.setQuantity(productID: limited.id, quantity: 99)
        check(cart.itemCount == 2, "Stepper must respect stock")
        cart.add(try product("empty", stock: 0))
        check(cart.items.count == 1, "Out of stock must not enter cart")
        cart.add(try product("unlimited"), quantity: Int.max)
        check(cart.items.last?.quantity == 99, "Global limit must apply without overflow")
        cart.add(try product("third"))
        cart.remove(at: IndexSet([0, 2]))
        check(cart.items.map(\.product.id) == ["unlimited"], "Batch deletion must use original indexes")
        check(CartStore(defaults: defaults).items == cart.items, "Cart must persist")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHTTP.self]
        let session = URLSession(configuration: config)
        let api = APIClient(session: session, baseURL: URL(string: "https://fixture.invalid")!)
        MockHTTP.handler = { _ in (200, """
        {"order":{"id":"order-1","order_number":1042,"created_at":"2026-01-01","status":"ordered"},"items":[],"logs":[]}
        """) }
        let order = try await api.trackOrder(id: "LQ-1042", email: "fixture@example.com")
        check(order.0.id == "order-1", "Tracking must decode nested order")
        for json in ["{\"status\":\"processing\"}", "{\"status\":\"complete\"}", "{\"status\":\"unpaid\",\"paymentStatus\":\"processing\"}"] {
            let status = try decode(json, as: CheckoutStatusResult.self)
            check(status.confirmationMessage == nil, "Unconfirmed status must never signal success")
            check(!status.canStartNewPayment, "Unresolved payment must not permit another charge")
        }
        let completed = try decode("{\"status\":\"complete\",\"orderId\":\"order-1\"}", as: CheckoutStatusResult.self)
        check(completed.confirmationMessage != nil, "Confirmed order must complete")
        let retry = try decode("{\"status\":\"unpaid\",\"paymentStatus\":\"requires_payment_method\"}", as: CheckoutStatusResult.self)
        check(retry.canStartNewPayment, "Declined payment may be retried")

        var refreshes = 0
        MockHTTP.handler = { request in
            if request.url!.query!.contains("refresh_token") {
                refreshes += 1
                return (200, "{\"access_token\":\"renewed\",\"refresh_token\":\"rotated\",\"expires_in\":3600,\"user\":{\"id\":\"user-1\",\"email\":\"fixture@example.com\"}}")
            }
            return (200, "{\"access_token\":\"expired\",\"refresh_token\":\"refresh\",\"expires_in\":0,\"user\":{\"id\":\"user-1\"}}")
        }
        let service = SupabaseService(session: session, baseURL: URL(string: "https://fixture.invalid")!, anonKey: "test", persistSession: false)
        _ = try await service.signInWithSession(email: "fixture@example.com", password: "fixture-only")
        async let first = service.validSession()
        async let second = service.validSession()
        let (a, b) = try await (first, second)
        check(a?.accessToken == "renewed" && b?.accessToken == "renewed", "Expired tokens must refresh")
        check(refreshes == 1, "Concurrent requests must share refresh")
        check(a?.refreshToken == "rotated", "Rotated refresh token must replace old token")
        await service.signOut()
        let signedOut = try await service.validSession()
        check(signedOut == nil, "Sign out must clear session")
        _ = try await service.signInWithSession(email: "fixture@example.com", password: "fixture-only")
        MockHTTP.handler = { _ in (400, "{\"error\":\"invalid_grant\"}") }
        do { _ = try await service.validSession(); preconditionFailure("Revoked refresh must fail") }
        catch AppError.unauthorized { checks += 1 }
        let revoked = try await service.validSession()
        check(revoked == nil, "Revoked session must not remain signed in")
        let admin = AdminAPI(session: session, baseURL: URL(string: "https://fixture.invalid")!)
        var loginOrigin: String?
        MockHTTP.handler = { request in
            loginOrigin = request.value(forHTTPHeaderField: "Origin")
            return (401, "{\"error\":\"Invalid password.\"}")
        }
        do { try await admin.login(password: "wrong"); preconditionFailure("Bad admin password must fail") }
        catch AppError.unauthorized { checks += 1 }
        check(loginOrigin == "https://fixture.invalid", "Admin writes must send Origin for the same-origin guard")
        var listQuery: String?
        MockHTTP.handler = { request in
            listQuery = request.url?.query
            return (200, """
            {"queue":"all","orders":[{"id":"o-1","order_number":1001,"created_at":"2026-01-01T00:00:00Z","status":"ordered","total_amount":15.5,"shipping_method":"pickup"}]}
            """)
        }
        let queue = try await admin.orders(queue: .all, status: nil, search: " LQ-1001 ")
        check(queue.first?.totalAmount == 15.5 && queue.first?.isPickup == true, "Admin queue must decode orders")
        check(listQuery?.contains("q=LQ-1001") == true, "Admin search must send the trimmed term")
        MockHTTP.handler = { _ in (200, """
        {"order":{"id":"o-1","order_number":1001,"created_at":"2026-01-01T00:00:00Z","status":"processing","total_amount":15.5,"shipping_method":"pickup"},
         "items":[{"id":"i-1","product_id":null,"product_name":"Yam","product_price":5,"quantity":3}],
         "logs":[{"id":"l-1","from_status":"ordered","to_status":"processing","changed_at":"2026-01-01T01:00:00Z","changed_by":"admin","note":null}]}
        """) }
        let detail = try await admin.order(id: "o-1")
        check(detail.order.displayNumber == "LQ-1001" && detail.items.count == 1 && detail.logs.count == 1, "Admin order detail must decode")
        check(OrderStatusFlow.next(after: "processing", shippingMethod: "pickup") == "ready_for_pickup", "Pickup flow must go to ready for pickup")
        check(OrderStatusFlow.next(after: "processing", shippingMethod: "standard") == "shipped", "Shipping flow must go to shipped")
        check(!OrderStatusFlow.choices(for: "pickup").contains("shipped"), "Pickup orders must not offer carrier statuses")
        check(OrderStatusFlow.next(after: "delivered", shippingMethod: nil) == nil, "Finished orders have no next step")
        check(OrderStatusFlow.label("delivered", shippingMethod: "pickup") == "Picked up", "Collected pickup orders read as picked up")
        check(StoreConfig.matches("Lace", filter: StoreConfig.fashionGroup), "Fashion filter must include lace")
        check(!StoreConfig.matches("Spices", filter: StoreConfig.fashionGroup), "Fashion filter must exclude groceries")
        check(StoreConfig.matches("Spices", filter: "Spices"), "Plain category filter must match exactly")
        let wa = StoreConfig.whatsAppURL(message: "Hi & hello")?.absoluteString ?? ""
        check(wa.hasPrefix("https://wa.me/1") && wa.contains("text=Hi%20%26%20hello"), "WhatsApp link must add +1 and encode the message")
        func shelfProduct(_ id: String, _ name: String, _ category: String, day: Int, image: Bool = true, stock: Bool = true) throws -> Product {
            let imageJSON = image ? "\"https://x.invalid/\(id).jpg\"" : "null"
            return try decode("""
            {"id":"\(id)","name":"\(name)","price":5,"category":"\(category)","in_stock":\(stock),"created_at":"2026-01-0\(day)","image_url":\(imageJSON)}
            """, as: Product.self)
        }
        let shelf = [
            try shelfProduct("a", "Neat Fufu", "Flours & Rice", day: 6),
            try shelfProduct("b", "Tanzol Tablet", "Non food", day: 9),
            try shelfProduct("c", "Gari", "Flours & Rice", day: 5),
            try shelfProduct("d", "Yam no photo", "Fresh Produce", day: 4, image: false),
            try shelfProduct("e", "Shea Butter", "Cosmetics", day: 3),
            try shelfProduct("f", "Cocoa Butter", "Cosmetics", day: 2),
            try shelfProduct("g", "Sold out Yam", "Fresh Produce", day: 1, stock: false),
        ]
        let staples = HomeMerchandising.staples(from: shelf)
        check(staples.map(\.id) == ["a"], "Staples need stock and a photo")
        let trending = HomeMerchandising.trending(from: shelf, excluding: Set(staples.map(\.id)))
        check(trending.first?.id == "c" && !trending.contains { $0.id == "a" }, "Trending leads with groceries and skips staples")
        check(trending.filter { $0.category == "Cosmetics" }.count == 1, "Trending caps cosmetics at one")
        print("PASS: \(checks) mobile regression checks (mock network; no live payments)")
    }
}
