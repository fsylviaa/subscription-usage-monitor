import SwiftUI
import UIKit
import UserNotifications

@main
struct SubscriptionUsageApp: App {
    @UIApplicationDelegateAdaptor(SubscriptionAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if QuotaStyleLabView.requested {
                QuotaStyleLabView()
            } else if CursorLoginProbeView.requested {
                CursorLoginProbeView()
            } else if GrokBotUsageProbeView.requested {
                GrokBotUsageProbeView()
            } else {
                productionRoot
            }
            #else
            productionRoot
            #endif
        }
    }

    private var productionRoot: some View {
            RootView(connection: AppBackgroundRuntime.shared.flow,
                     preferences: AppBackgroundRuntime.shared.preferences,
                     onBackground: { Task { await AppBackgroundRuntime.shared.coordinator.scheduleIfNeeded() } },
                     reminderScheduler: AppBackgroundRuntime.shared.reminderScheduler)
    }
}

final class SubscriptionAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        if QuotaStyleLabView.requested || CursorLoginProbeView.requested || GrokBotUsageProbeView.requested { return true }
        #endif
        // Install before launch finishes so cold-start notification responses survive.
        UNUserNotificationCenter.current().delegate = self
        AppBackgroundRuntime.shared.register()
        #if DEBUG
        CodexConnectionUITestSupport.injectNotificationLaunchIfRequested()
        #endif
        return true
    }
}


extension SubscriptionAppDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        let event = ResetReminderOpenEvent(request: response.notification.request,
                                          actionIdentifier: response.actionIdentifier)
        await MainActor.run {
            if let event { ResetReminderNavigation.shared.receive(event) }
        }
        // Return without waiting for storage, login restoration or networking.
    }
}

/// Parses the stable identity already present in v1 scheduled reminders. Old
/// notifications remain usable without replacing/reissuing their system requests.
struct ResetReminderTarget: Equatable, Sendable {
    let accountID: UUID
    let bindingKey: String
    let window: QuotaWindow
    let resetsAt: Date

    nonisolated init?(request: UNNotificationRequest) {
        let prefix = SystemResetReminderNotificationCenter.namespace
        guard request.identifier.hasPrefix(prefix) else { return nil }
        let fields = request.identifier.dropFirst(prefix.count).split(separator: ".", maxSplits: 3, omittingEmptySubsequences: false)
        guard fields.count == 4, let id = UUID(uuidString: String(fields[0])),
              fields[1].count == 64, fields[1].allSatisfy({ "0123456789abcdef".contains($0) }),
              let rawWindow = Int(fields[2]), let window = QuotaWindow(rawValue: rawWindow),
              let seconds = Double(fields[3]), seconds.isFinite,
              (1...253_402_300_799).contains(seconds),
              let metadataID = request.content.userInfo["accountID"] as? String,
              UUID(uuidString: metadataID) == id,
              request.content.userInfo["window"] as? Int == rawWindow else { return nil }
        accountID = id; bindingKey = String(fields[1]); self.window = window
        resetsAt = Date(timeIntervalSince1970: seconds)
    }

    func detailTarget(in accounts: [ConnectedAccount]) -> CodexDetailTarget? {
        guard let account = accounts.first(where: { $0.id == accountID }),
              !account.isDemo, account.deletionPending != true,
              account.hasKnownProductPair,
              bindingKey == ResetReminderPlan.bindingKey(account) else { return nil }
        return CodexDetailTarget(account)
    }
}

struct ResetReminderOpenEvent: Equatable, Sendable {
    let id = UUID()
    let target: ResetReminderTarget?

    nonisolated init?(request: UNNotificationRequest, actionIdentifier: String) {
        guard actionIdentifier == UNNotificationDefaultActionIdentifier,
              request.identifier.hasPrefix(SystemResetReminderNotificationCenter.namespace) else { return nil }
        // A malformed owned target falls back to the current quota page. Foreign
        // notifications and dismiss actions don't change the user's navigation.
        target = ResetReminderTarget(request: request)
    }
}

@MainActor
final class ResetReminderNavigation: ObservableObject {
    static let shared = ResetReminderNavigation()
    @Published private(set) var pending: ResetReminderOpenEvent?

    func receive(_ event: ResetReminderOpenEvent) { pending = event }
    func consume(_ id: UUID) {
        if pending?.id == id { pending = nil }
    }
}
