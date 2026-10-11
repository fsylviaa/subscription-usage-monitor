import SwiftUI
import UIKit

@main
struct SubscriptionUsageApp: App {
    @UIApplicationDelegateAdaptor(SubscriptionAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView(connection: AppBackgroundRuntime.shared.flow,
                     preferences: AppBackgroundRuntime.shared.preferences,
                     onBackground: { Task { await AppBackgroundRuntime.shared.coordinator.scheduleIfNeeded() } },
                     reminderScheduler: AppBackgroundRuntime.shared.reminderScheduler)
        }
    }
}

final class SubscriptionAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AppBackgroundRuntime.shared.register()
        return true
    }
}
