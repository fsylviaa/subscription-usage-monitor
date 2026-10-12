import Foundation
import UserNotifications

@MainActor
protocol ResetReminderNotificationCenter {
    func pendingRequests() async -> [ResetReminderRequest]
    func deliveredRequests() async -> [ResetReminderRequest]
    func add(_ request: ResetReminderRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
}

extension ResetReminderNotificationCenter {
    func deliveredRequests() async -> [ResetReminderRequest] { [] }
}

/// The only adapter that writes to the system. Test and preview composition
/// never installs this adapter; constructing calendar requests alone is pure.
@MainActor
struct SystemResetReminderNotificationCenter: ResetReminderNotificationCenter {
    nonisolated static let namespace = "quota-reset.v1."

    func pendingRequests() async -> [ResetReminderRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().compactMap(Self.decode)
    }

    func deliveredRequests() async -> [ResetReminderRequest] {
        await UNUserNotificationCenter.current().deliveredNotifications().compactMap { Self.decode($0.request) }
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

/// Scheduled elapsed rounds are processed, not evidence of actual delivery.
/// Keeping them prevents replays after dismissal, relaunch, or a clock rollback.
struct ResetReminderJournal: Codable {
    var processed: Set<String> = []
    var scheduled: [String: Date] = [:]

    mutating func observe(pending: [ResetReminderRequest], delivered: [ResetReminderRequest], now: Date) {
        for request in pending where request.identifier.hasPrefix(SystemResetReminderNotificationCenter.namespace) {
            scheduled[request.identifier] = request.resetsAt
        }
        processed.formUnion(delivered.map(\.identifier))
        processed.formUnion(scheduled.filter { $0.value <= now }.map(\.key))
        scheduled = scheduled.filter { !processed.contains($0.key) }
    }
}

/// Serializes local updates and, in production, App/extension access with a
/// shared file lease. Unknown/unreadable input pauses rather than erasing data.
@MainActor
final class ResetReminderScheduler {
    struct Input: Equatable {
        let accounts: [ConnectedAccount]
        let wantsReminders: Bool
        let authorization: ResetReminderAuthorizationStatus
    }
    private let center: any ResetReminderNotificationCenter
    private let journalURL: URL?
    private let currentInput: (() async throws -> Input)?
    private var journal = ResetReminderJournal()
    private let now: () -> Date
    private var latest: Input?
    private var revision: UInt64 = 0
    private var worker: Task<Void, Never>?
    private(set) var lastResult: ResetReminderSchedulingResult?

    init(center: any ResetReminderNotificationCenter, now: @escaping () -> Date = { Date() },
         journalURL: URL? = nil, currentInput: (() async throws -> Input)? = nil) {
        self.center = center
        self.now = now
        self.journalURL = journalURL
        self.currentInput = currentInput
    }

    func reconcileSavedInput() async {
        guard let currentInput else { return }
        do {
            let input = try await currentInput()
            if input.authorization == .unknown && input.wantsReminders { suspend(); return }
            await update(accounts: input.accounts, wantsReminders: input.wantsReminders,
                         authorization: input.authorization)
        } catch { suspend() }
    }

    private func refreshInput(version: UInt64) async -> Bool {
        guard version == revision else { return false }
        if let currentInput {
            do {
                let input = try await currentInput()
                guard version == revision else { return false }
                if input.wantsReminders && input.authorization == .unknown { suspend(); return false }
                if input != latest { latest = input; revision &+= 1; return false }
            } catch {
                if version == revision { suspend() }
                return false
            }
        }
        return version == revision
    }

    private func saveJournal() throws {
        guard let journalURL else { return }
        try JSONEncoder().encode(journal).write(to: journalURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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

    private func cancelObsoleteWithoutJournal() async {
        while let input = latest {
            let version = revision
            guard await refreshInput(version: version) else { continue }
            let pending = await center.pendingRequests()
            guard await refreshInput(version: version) else { continue }
            let desired = Set(ResetReminderPlan.requests(accounts: input.accounts,
                wantsReminders: input.wantsReminders, authorization: input.authorization, now: now()).map(\.identifier))
            center.removePendingRequests(withIdentifiers: pending.filter {
                $0.identifier.hasPrefix(SystemResetReminderNotificationCenter.namespace) && !desired.contains($0.identifier)
            }.map(\.identifier))
            return
        }
    }

    private func drain() async {
        defer { worker = nil }
        var lease: SharedFileLease?
        if let journalURL {
            for _ in 0..<40 {
                do { lease = try SharedFileLease(url: journalURL.appendingPathExtension("lock")); break }
                catch SharedFileLease.LockError.busy { try? await Task.sleep(for: .milliseconds(50)) }
                catch { return }
            }
            guard lease != nil else { return }
            do {
                do { journal = try JSONDecoder().decode(ResetReminderJournal.self, from: Data(contentsOf: journalURL)) }
                catch CocoaError.fileReadNoSuchFile { journal = ResetReminderJournal() }
            } catch { await cancelObsoleteWithoutJournal(); return }
        }
        defer { withExtendedLifetime(lease) {} }
        while let input = latest {
            let version = revision
            guard await refreshInput(version: version) else { continue }
            let pending = await center.pendingRequests()
            let delivered = await center.deliveredRequests()
            guard await refreshInput(version: version) else { continue }
            journal.observe(pending: pending, delivered: delivered, now: now())
            do { try saveJournal() } catch { await cancelObsoleteWithoutJournal(); return }
            let planned = ResetReminderPlan.requests(accounts: input.accounts,
                wantsReminders: input.wantsReminders, authorization: input.authorization, now: now())
                .filter { !journal.processed.contains($0.identifier) }
            let desiredIDs = Set(planned.map(\.identifier))
            let obsolete = pending.filter {
                $0.identifier.hasPrefix(SystemResetReminderNotificationCenter.namespace) && !desiredIDs.contains($0.identifier)
            }.map(\.identifier)
            center.removePendingRequests(withIdentifiers: obsolete)
            for identifier in obsolete { journal.scheduled.removeValue(forKey: identifier) }
            do { try saveJournal() } catch { await cancelObsoleteWithoutJournal(); return }
            var failures: [String] = []
            for request in planned {
                guard await refreshInput(version: version) else { break }
                guard request.resetsAt > now() else { continue }
                if pending.contains(where: { Self.matches($0, request) }) { continue }
                do { try await center.add(request) }
                catch { failures.append(request.identifier) }
            }
            guard await refreshInput(version: version) else { continue }
            let actual = await center.pendingRequests()
            guard await refreshInput(version: version) else { continue }
            let accepted = actual.filter { actual in planned.contains { Self.matches(actual, $0) } }
            for request in accepted { journal.scheduled[request.identifier] = request.resetsAt }
            do { try saveJournal() } catch { await cancelObsoleteWithoutJournal(); return }
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

/// A single shared preference lets the extension follow the same global switch.
/// Isolated stores/settings never call this runtime or touch the shared container.
@MainActor
enum SharedResetReminderRuntime {
    private static var scheduler: ResetReminderScheduler?
    private static var directory: URL {
        get throws { try WidgetSnapshotStore.sharedDirectory().deletingLastPathComponent().appendingPathComponent("Reminders") }
    }

    static var preferences: UserDefaults? { UserDefaults(suiteName: WidgetSnapshotStore.appGroupIdentifier) }

    /// Preserve T38's existing preference on upgrade; subsequent App/extension
    /// reads use this one shared preference, not competing per-process copies.
    static func migratePreference(from legacy: UserDefaults, to shared: UserDefaults? = preferences) {
        guard let preferences = shared, preferences.object(forKey: ResetReminderSettings.preferenceKey) == nil else { return }
        preferences.set(legacy.bool(forKey: ResetReminderSettings.preferenceKey),
                        forKey: ResetReminderSettings.preferenceKey)
    }

    static func liveScheduler() -> ResetReminderScheduler? {
        guard ResetReminderRuntime.permitsSystemScheduling(arguments: ProcessInfo.processInfo.arguments,
            isTestHost: NSClassFromString("XCTestCase") != nil) else { return nil }
        if let scheduler { return scheduler }
        guard let journalURL = try? directory.appendingPathComponent("rounds.json") else { return nil }
        let result = ResetReminderScheduler(center: SystemResetReminderNotificationCenter(), journalURL: journalURL,
            currentInput: {
                guard let preferences, let enabled = preferences.object(forKey: ResetReminderSettings.preferenceKey) as? Bool else {
                    throw CocoaError(.fileReadNoSuchFile)
                }
                let authorization = try await SystemResetReminderAuthorizationService().authorizationStatus()
                // Explicit switch-off/revocation can clear pending requests even if accounts are protected.
                if !enabled || !authorization.permitsReminders {
                    return .init(accounts: [], wantsReminders: enabled, authorization: authorization)
                }
                let store = try AccountStore.widgetAccountStore()
                let accounts = try await store.load()
                return .init(accounts: accounts, wantsReminders: enabled, authorization: authorization)
            })
        scheduler = result
        return result
    }

    static func reconcile() async { await liveScheduler()?.reconcileSavedInput() }
}
