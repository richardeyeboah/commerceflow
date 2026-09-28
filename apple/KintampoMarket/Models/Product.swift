import Foundation

struct Product: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String?
    let price: Double
    let category: String
    let imageURL: String?
    let imageURLs: [String]?
    let inStock: Bool
    let createdAt: String
    let brand: String?
    let dietaryTags: [String]?
    let stockQuantity: Int?
    let unitAmount: Double?
    let unitOfMeasure: String?
    let packLabel: String?
    let variantGroup: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, price, category, brand
        case imageURL = "image_url"
        case imageURLs = "image_urls"
        case inStock = "in_stock"
        case createdAt = "created_at"
        case dietaryTags = "dietary_tags"
        case stockQuantity = "stock_quantity"
        case unitAmount = "unit_amount"
        case unitOfMeasure = "unit_of_measure"
        case packLabel = "pack_label"
        case variantGroup = "variant_group"
    }

    var maxCartQuantity: Int {
        guard effectiveInStock else { return 0 }
        return min(99, max(0, stockQuantity ?? 99))
    }

    var primaryImageURL: URL? {
        if let first = imageURLs?.first, let url = URL(string: first) { return url }
        if let imageURL, let url = URL(string: imageURL) { return url }
        return nil
    }

    var displayPrice: String {
        String(format: "$%.2f", price)
    }

    /// "$1.29/lb" when unit amount and measure are set.
    var unitPriceLabel: String? {
        guard let unitAmount, unitAmount > 0 else { return nil }
        let measure = (unitOfMeasure ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !measure.isEmpty else { return nil }
        let per = price / unitAmount
        guard per > 0 else { return nil }
        return String(format: "$%.2f/%@", per, measure)
    }

    var effectiveInStock: Bool {
        if let stockQuantity, stockQuantity <= 0 { return false }
        return inStock
    }
}

struct CartItem: Identifiable, Codable, Hashable, Sendable {
    var id: String { product.id }
    let product: Product
    var quantity: Int

    var lineTotal: Double { product.price * Double(quantity) }
}

struct TrackedOrder: Codable, Sendable {
    let id: String
    let orderNumber: Int?
    let createdAt: String
    let status: String
    let customerName: String?
    let customerEmail: String?
    let totalAmount: Double?
    let shippingMethod: String?
    let trackingNumber: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case orderNumber = "order_number"
        case createdAt = "created_at"
        case customerName = "customer_name"
        case customerEmail = "customer_email"
        case totalAmount = "total_amount"
        case shippingMethod = "shipping_method"
        case trackingNumber = "tracking_number"
    }

    var displayNumber: String {
        if let orderNumber { return "LQ-\(orderNumber)" }
        return id.prefix(8).uppercased()
    }
}

struct UserProfile: Codable, Sendable {
    let id: String
    let fullName: String?
    let phone: String?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case id, phone, role
        case fullName = "full_name"
    }
}

struct OrderLineItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let productId: String?
    let productName: String
    let productPrice: Double
    let quantity: Int

    enum CodingKeys: String, CodingKey {
        case id
        case productId = "product_id"
        case productName = "product_name"
        case productPrice = "product_price"
        case quantity
    }
}

struct ProductReview: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let reviewerName: String
    let rating: Int
    let comment: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, rating, comment
        case reviewerName = "reviewer_name"
        case createdAt = "created_at"
    }
}

struct RecipeSummary: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let slug: String
    let title: String
    let summary: String?
    let imageURL: String?
    let prepMinutes: Int?
    let cookMinutes: Int?
    let servings: Int?
    let body: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, title, summary, servings
        case imageURL = "image_url"
        case prepMinutes = "prep_minutes"
        case cookMinutes = "cook_minutes"
        case body = "body_md"
    }
}

struct RecipeIngredientLine: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let quantity: Double
    let productId: String?

    enum CodingKeys: String, CodingKey {
        case id, label, quantity
        case productId = "product_id"
    }
}

struct OrderTrackingResponse: Decodable {
    let order: TrackedOrder
    let items: [OrderLineItem]?
}
