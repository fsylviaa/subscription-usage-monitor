import Foundation
import UserNotifications

@MainActor
protocol ResetReminderNotificationCenter {
    func pendingRequests() async -> [ResetReminderRequest]
    func add(_ request: ResetReminderRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
}

/// The only adapter that writes to the system. Test and preview composition
/// never installs this adapter; constructing calendar requests alone is pure.
@MainActor
struct SystemResetReminderNotificationCenter: ResetReminderNotificationCenter {
    static let namespace = "quota-reset.v1."

    func pendingRequests() async -> [ResetReminderRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().compactMap(Self.decode)
    }

    func add(_ request: ResetReminderRequest) async throws {
        try await UNUserNotificationCenter.current().add(Self.makeRequest(request))
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: identifiers.filter { $0.hasPrefix(Self.namespace) })
    }

    static func makeRequest(_ request: ResetReminderRequest) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = ["accountID": request.accountID.uuidString, "window": request.window.rawValue]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // Calendar triggers have second precision. Round up, never before the
        // reported reset, and pin UTC so travel/DST cannot move the instant.
        let date = Date(timeIntervalSince1970: ceil(request.resetsAt.timeIntervalSince1970))
        var components = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return UNNotificationRequest(identifier: request.identifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    /// Read the actual stored trigger and content, not our intended time from
    /// userInfo or the success callback. Delivered notifications are not pending.
    static func decode(_ request: UNNotificationRequest) -> ResetReminderRequest? {
        guard request.identifier.hasPrefix(namespace),
              let rawID = request.content.userInfo["accountID"] as? String,
              let accountID = UUID(uuidString: rawID),
              let rawWindow = request.content.userInfo["window"] as? Int,
              let window = QuotaWindow(rawValue: rawWindow),
              let trigger = request.trigger as? UNCalendarNotificationTrigger, !trigger.repeats,
              let date = trigger.dateComponents.calendar?.date(from: trigger.dateComponents) else { return nil }
        return ResetReminderRequest(identifier: request.identifier, accountID: accountID,
            window: window, resetsAt: date, title: request.content.title, body: request.content.body)
    }
}

struct ResetReminderSchedulingResult {
    let planned: [ResetReminderRequest]
    /// Only requests read back with matching identity, content and trigger.
    let accepted: [ResetReminderRequest]
    let failedIdentifiers: [String]
}

/// Serializes pending-center access. Minimal cleanup prevents an in-flight
/// initial arrangement surviving a switch-off or a newer account snapshot.
/// The full lifecycle / delivered-round acceptance remains T40.
@MainActor
final class ResetReminderScheduler {
    private struct Input {
        let accounts: [ConnectedAccount]
        let wantsReminders: Bool
        let authorization: ResetReminderAuthorizationStatus
    }
    private let center: any ResetReminderNotificationCenter
    private let now: () -> Date
    private var latest: Input?
    private var revision: UInt64 = 0
    private var worker: Task<Void, Never>?
    private(set) var lastResult: ResetReminderSchedulingResult?

    init(center: any ResetReminderNotificationCenter, now: @escaping () -> Date = { Date() }) {
        self.center = center
        self.now = now
    }

    func update(accounts: [ConnectedAccount], wantsReminders: Bool,
                authorization: ResetReminderAuthorizationStatus) async {
        latest = Input(accounts: accounts, wantsReminders: wantsReminders, authorization: authorization)
        revision &+= 1
        lastResult = nil
        if let worker { await worker.value; return }
        let work = Task { @MainActor in await self.drain() }
        worker = work
        await work.value
    }

    /// Unknown permission or an unavailable account read is not proof that
    /// valid pending reminders became obsolete. Stop further writes, retain
    /// existing requests, and wait for a confirmed input before reconciling.
    func suspend() {
        revision &+= 1
        latest = nil
        lastResult = nil
    }

    private func drain() async {
        defer { worker = nil }
        while let input = latest {
            let version = revision
            let planned = ResetReminderPlan.requests(accounts: input.accounts,
                wantsReminders: input.wantsReminders, authorization: input.authorization, now: now())
            let pending = await center.pendingRequests()
            guard version == revision else { continue }
            let desiredIDs = Set(planned.map(\.identifier))
            let obsolete = pending.filter {
                $0.identifier.hasPrefix(SystemResetReminderNotificationCenter.namespace) && !desiredIDs.contains($0.identifier)
            }.map(\.identifier)
            center.removePendingRequests(withIdentifiers: obsolete)
            var failures: [String] = []
            for request in planned {
                guard version == revision else { break }
                guard request.resetsAt > now() else { continue }
                if pending.contains(where: { Self.matches($0, request) }) { continue }
                do { try await center.add(request) }
                catch { failures.append(request.identifier) }
            }
            guard version == revision else { continue }
            let actual = await center.pendingRequests()
            guard version == revision else { continue }
            let accepted = actual.filter { actual in planned.contains { Self.matches(actual, $0) } }
            lastResult = ResetReminderSchedulingResult(planned: planned, accepted: accepted,
                failedIdentifiers: failures)
            return
        }
    }

    private static func matches(_ actual: ResetReminderRequest, _ planned: ResetReminderRequest) -> Bool {
        let delay = actual.resetsAt.timeIntervalSince(planned.resetsAt)
        return actual.identifier == planned.identifier && actual.accountID == planned.accountID
            && actual.window == planned.window && actual.title == planned.title && actual.body == planned.body
            && delay >= 0 && delay < 1
    }
}

/// RootView's default remains disconnected. Only the ordinary App composition
/// can inject system writes, including in Debug; all fixture launches stay inert.
enum ResetReminderRuntime {
    static func permitsSystemScheduling(arguments: [String], isTestHost: Bool) -> Bool {
        !isTestHost && !arguments.contains { $0.hasPrefix("--t") || $0 == "--management-ui" }
    }
}
