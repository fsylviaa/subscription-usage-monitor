import SwiftUI

@main
struct SubscriptionUsageApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            RootView(connection: CodexConnectionUITestSupport.makeFlow())
            #else
            RootView()
            #endif
        }
    }
}
