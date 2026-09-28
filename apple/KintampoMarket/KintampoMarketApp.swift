import SwiftUI
#if os(iOS)
import StripePaymentSheet
#endif

@main
struct KintampoMarketApp: App {
    @Environment(\.scenePhase) private var scenePhase
    init() {
        // Kick off catalog fetch as soon as the process starts.
        Task { @MainActor in
            await CatalogStore.shared.loadIfNeeded()
        }
    }

    var body: some Scene {
        #if os(watchOS)
        WindowGroup {
            WatchRootView()
        }
        #else
        WindowGroup {
            RootTabView()
                .task { await AuthStore.shared.hydrate() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await AuthStore.shared.hydrate() } }
                }
                #if os(iOS)
                .onOpenURL { url in
                    if StripeAPI.handleURLCallback(with: url) { return }
                    AppRouter.shared.open(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { AppRouter.shared.open(url) }
                }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif
        #endif
    }
}
