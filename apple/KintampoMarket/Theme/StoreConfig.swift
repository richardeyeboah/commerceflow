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

    static let productCategories: [String] = [
        "African Prints", "Alcohol", "Beverages", "Bread", "Brocade", "Canned",
        "Caribbean product", "Cosmetics", "Dairy And Tea", "Flours & Rice",
        "Fresh Produce", "Frozen foods", "Hair & Braiding", "Headtie", "Kente",
        "Lace", "Meat and Seafood", "Motherland", "Non food", "Ready-to-wear",
        "Snack", "Spices",
    ]
}
