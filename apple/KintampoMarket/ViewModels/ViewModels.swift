import Foundation
import Observation

@Observable
@MainActor
final class OrderTrackViewModel {
    var orderID = ""
    var email = ""
    var order: TrackedOrder?
    var items: [OrderLineItem] = []
    var errorMessage: String?
    var isLoading = false

    func track() async {
        errorMessage = nil
        order = nil
        items = []
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await APIClient.shared.trackOrder(id: orderID, email: email)
            order = result.0
            items = result.1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
