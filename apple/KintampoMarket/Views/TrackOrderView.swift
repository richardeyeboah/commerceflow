import SwiftUI

struct TrackOrderView: View {
    @State private var tracker = OrderTrackViewModel()

    var body: some View {
        Form {
            Section("Order lookup") {
                TextField("Order # (e.g. LQ-1042)", text: $tracker.orderID)
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                TextField("Email used at checkout", text: $tracker.email)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                Button(tracker.isLoading ? "Looking up…" : "Track order") {
                    Task { await tracker.track() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(tracker.orderID.isEmpty || tracker.email.isEmpty || tracker.isLoading)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if let error = tracker.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            if let order = tracker.order {
                Section("Status") {
                    LabeledContent("Order", value: order.displayNumber)
                    LabeledContent("Status", value: order.status.replacingOccurrences(of: "_", with: " ").capitalized)
                    if let total = order.totalAmount {
                        LabeledContent("Total") {
                            Text(String(format: "$%.2f", total)).foregroundStyle(Brand.red).fontWeight(.semibold)
                        }
                    }
                    if let tracking = order.trackingNumber, !tracking.isEmpty {
                        LabeledContent("Tracking", value: tracking)
                    }
                }
                if !tracker.items.isEmpty {
                    Section("Items") {
                        ForEach(tracker.items) { item in
                            Text("\(item.quantity)× \(item.productName)")
                        }
                        NavigationLink("Order details") {
                            OrderDetailView(order: order, presetItems: tracker.items)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.surface)
        .navigationTitle("Track")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
