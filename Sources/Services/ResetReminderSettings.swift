import Combine
import Foundation
import UserNotifications

enum ResetReminderAuthorizationStatus: Equatable, Sendable {
    case unknown
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var permitsReminders: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: true
        case .unknown, .notDetermined, .denied: false
        }
    }
}

@MainActor
protocol ResetReminderAuthorizationServing {
    func authorizationStatus() async throws -> ResetReminderAuthorizationStatus
    func requestAuthorization() async throws
}

@MainActor
struct SystemResetReminderAuthorizationService: ResetReminderAuthorizationServing {
    func authorizationStatus() async throws -> ResetReminderAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }

    func requestAuthorization() async throws {
        // The subsequent settings read, rather than this Boolean result, is
        // authoritative. This task never schedules or sends a notification.
        _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}

@MainActor
final class ResetReminderSettings: ObservableObject {
    static let preferenceKey = "resetReminder.wantsReminders"

    @Published private(set) var wantsReminders: Bool
    @Published private(set) var authorizationStatus: ResetReminderAuthorizationStatus = .unknown
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRequestingAuthorization = false
    @Published private(set) var hasError = false

    var isEnabled: Bool {
        wantsReminders && !isRefreshing && authorizationStatus.permitsReminders
    }

    var showsSystemSettings: Bool {
        wantsReminders && !isRefreshing && authorizationStatus == .denied
    }

    private let defaults: UserDefaults
    private let authorizationService: any ResetReminderAuthorizationServing
    private var readRevision: UInt64 = 0
    private var enableOperation: (id: UUID, task: Task<Void, Never>)?

    init(defaults: UserDefaults = .standard,
         authorizationService: any ResetReminderAuthorizationServing = SystemResetReminderAuthorizationService()) {
        self.defaults = defaults
        self.authorizationService = authorizationService
        wantsReminders = defaults.bool(forKey: Self.preferenceKey)
    }

    /// Only this explicit user action may start the system authorization prompt.
    func setEnabled(_ enabled: Bool) async {
        wantsReminders = enabled
        defaults.set(enabled, forKey: Self.preferenceKey)
        hasError = false
        guard enabled else { return }

        if let operation = enableOperation {
            await operation.task.value
            return
        }
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.enableIfPermitted()
            if self.enableOperation?.id == id { self.enableOperation = nil }
        }
        enableOperation = (id, task)
        await task.value
    }

    /// Opening the app, returning from Settings, and visiting this screen only
    /// read permission. A saved preference never triggers a permission prompt.
    func refreshAuthorization() async {
        if let operation = enableOperation { await operation.task.value }
        _ = await readAuthorization()
    }

    private func enableIfPermitted() async {
        guard let status = await readAuthorization(), wantsReminders,
              status == .notDetermined else { return }
        isRequestingAuthorization = true
        do {
            try await authorizationService.requestAuthorization()
        } catch {
            authorizationStatus = .unknown
            hasError = true
            isRequestingAuthorization = false
            return
        }
        isRequestingAuthorization = false
        // Even if the user turned the switch off during the dialog, record the
        // actual system state while preserving their latest saved preference.
        _ = await readAuthorization()
    }

    @discardableResult
    private func readAuthorization() async -> ResetReminderAuthorizationStatus? {
        readRevision &+= 1
        let revision = readRevision
        isRefreshing = true
        hasError = false
        do {
            let status = try await authorizationService.authorizationStatus()
            guard revision == readRevision else { return nil }
            authorizationStatus = status
            isRefreshing = false
            return status
        } catch {
            guard revision == readRevision else { return nil }
            authorizationStatus = .unknown
            isRefreshing = false
            hasError = true
            return nil
        }
    }
}
