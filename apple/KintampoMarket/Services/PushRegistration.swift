import Foundation

#if os(iOS)
import UIKit
import UserNotifications

enum PushRegistration {
    @MainActor
    static func registerIfPossible(ask: Bool = false) async {
        // Simulator and unsigned local builds have no push entitlement.
        #if targetEnvironment(simulator)
        return
        #else
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let granted: Bool
        if settings.authorizationStatus == .notDetermined {
            guard ask else { return }
            granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        } else if ask, settings.authorizationStatus == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            return
        } else {
            granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        }
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }
}
#endif
