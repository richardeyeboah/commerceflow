import Foundation

enum StoreConfig {
    static let name = "Kintampo African Market"
    static let shortName = "Kintampo Market"
    static let tagline = "Groceries from Ghana & the Caribbean."
    static let address = "1668 E Dublin Granville Rd, Columbus, OH 43229"
    static let hours = "Mon–Sat 9am–8pm · Sun 10am–6pm"

    static var supportEmail: String {
        let e = AppConfig.supportEmail
        return e.isEmpty ? "kalebdoffour@gmail.com" : e
    }

    static var phone: String {
        let digits = AppConfig.storePhone.filter(\.isNumber)
        guard digits.count == 10 else { return "(614) 377-8297" }
        let a = digits.prefix(3)
        let b = digits.dropFirst(3).prefix(3)
        let c = digits.suffix(4)
        return "(\(a)) \(b)-\(c)"
    }

    static let freeShippingThreshold = 120

    /// Suggested in Shop search; only terms that match stocked products are shown.
    static let popularSearches = ["fufu", "gari", "yam", "plantain", "palm oil", "shito", "malta", "shea butter", "kente", "suya"]

    /// `wa.me` chat link to the store with a prefilled message (US numbers get the +1 country code).
    static func whatsAppURL(message: String) -> URL? {
        var digits = AppConfig.whatsAppNumber.filter(\.isNumber)
        if digits.isEmpty { digits = phone.filter(\.isNumber) }
        if digits.count == 10 { digits = "1" + digits }
        var components = URLComponents(string: "https://wa.me/\(digits)")
        components?.queryItems = [URLQueryItem(name: "text", value: message)]
        return components?.url
    }

    /// Category photos the website already serves from `public/images/categories`.
    static func categoryImageURL(_ category: String) -> URL? {
        let files = [
            "African Prints": "african-prints.jpg", "Beverages": "beverages.png", "Bread": "bread.png",
            "Canned": "canned.jpg", "Caribbean product": "caribbean-product.jpg", "Cosmetics": "cosmetics.jpg",
            "Dairy And Tea": "dairy-and-tea.jpg", "Flours & Rice": "flours-rice.jpg",
            "Fresh Produce": "fresh-produce.jpg", "Frozen foods": "frozen-foods.jpg",
            "Meat and Seafood": "meat-seafood.jpg", "Motherland": "motherland.jpg",
            "Non food": "non-food.jpg", "Snack": "snack.jpg", "Spices": "spices.jpg",
        ]
        guard let file = files[category] else { return nil }
        return AppConfig.siteURL.appending(path: "images/categories/\(file)")
    }

    /// Matches `FASHION_CATEGORIES` + legacy `Wax` in `lib/constants/categories.ts`.
    static let fashionGroup = "Fashion"
    static let fashionCategories: Set<String> = [
        "African Prints", "Lace", "Headtie", "Kente", "Brocade", "Ready-to-wear", "Hair & Braiding", "Wax",
    ]

    /// True when `product` belongs to a Shop filter (a real category or the Fashion group).
    static func matches(_ category: String, filter: String) -> Bool {
        filter == fashionGroup ? fashionCategories.contains(category) : category == filter
    }
}
