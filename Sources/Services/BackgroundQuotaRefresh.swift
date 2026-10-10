import BackgroundTasks
import Foundation
import UIKit

struct BackgroundQuotaResult: Codable, Equatable {
    let total: Int
    let succeeded: Int
    let failed: Int
    let loaded: Bool
    var success: Bool { loaded && failed == 0 }
}

/// No email, account identifiers, quota amounts or credentials in this journal.
/// A request is evidence of scheduling only, never evidence of execution.
struct BackgroundRefreshEvent: Codable, Equatable {
    let kind: String
    let source: String
    let at: Date
    var target: Date?
    var wasInBackground: Bool?
    var result: BackgroundQuotaResult?
    var successTimes: [Date]?
}

@MainActor
protocol BackgroundRefreshScheduling {
    func pendingTargets() async -> [Date]
    func submit(earliest: Date) throws
}

@MainActor
struct SystemBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    func pendingTargets() async -> [Date] {
        await BGTaskScheduler.shared.pendingTaskRequests()
            .filter { $0.identifier == BackgroundQuotaRefresh.identifier }.compactMap(\.earliestBeginDate)
    }
    func submit(earliest: Date) throws {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundQuotaRefresh.identifier)
        request.earliestBeginDate = earliest
        try BGTaskScheduler.shared.submit(request)
    }
}

@MainActor
final class BackgroundQuotaRefresh {
    static let identifier = "com.iceflying.SubscriptionUsage.refresh"
    static let interval: TimeInterval = 30 * 60
    let flow: CodexConnectionFlow
    private let scheduler: any BackgroundRefreshScheduling
    private let journalURL: URL
    private let now: () -> Date
    private let enabled: Bool
    private var scheduling = false
    private(set) var events: [BackgroundRefreshEvent]
    private(set) var journalWriteSucceeded = true

    init(flow: CodexConnectionFlow, scheduler: any BackgroundRefreshScheduling = SystemBackgroundRefreshScheduler(),
         journalURL: URL, enabled: Bool = true, now: @escaping () -> Date = { Date() }) {
        self.flow = flow; self.scheduler = scheduler; self.journalURL = journalURL
        self.enabled = enabled; self.now = now
        events = (try? JSONDecoder().decode([BackgroundRefreshEvent].self, from: Data(contentsOf: journalURL))) ?? []
    }

    func record(_ event: BackgroundRefreshEvent) {
        events.append(event)
        events = Array(events.suffix(100))
        do {
            try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(events).write(to: journalURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            journalWriteSucceeded = true
        } catch { journalWriteSucceeded = false }
    }

    func scheduleIfNeeded() async {
        guard enabled, !scheduling else { return }
        scheduling = true
        defer { scheduling = false }
        // Frequent foreground/background transitions must not postpone the
        // already requested opportunity by another half hour each time.
        if let pending = await scheduler.pendingTargets().min() {
            record(.init(kind: "alreadyScheduled", source: "request", at: now(), target: pending))
            return
        }
        let time = now()
        let target = time.addingTimeInterval(Self.interval)
        do {
            try scheduler.submit(earliest: target)
            record(.init(kind: "scheduled", source: "request", at: time, target: target))
        } catch {
            record(.init(kind: "scheduleFailed", source: "request", at: time, target: target))
        }
    }

    func execute(source: String, wasInBackground: Bool) async -> BackgroundQuotaResult {
        record(.init(kind: "started", source: source, at: now(), wasInBackground: wasInBackground,
                     successTimes: flow.accounts.compactMap { $0.quotaSnapshot?.observedAt }))
        await scheduleIfNeeded()
        let result = await flow.refreshQuotaInBackground()
        record(.init(kind: "finished", source: source, at: now(), wasInBackground: wasInBackground,
                     result: result, successTimes: flow.accounts.compactMap { $0.quotaSnapshot?.observedAt }))
        return result
    }

    func handle(_ task: BGTask, source: String) {
        let inBackground = UIApplication.shared.applicationState == .background
        var completed = false
        let finish: (Bool) -> Void = { success in
            guard !completed else { return }
            completed = true
            task.setTaskCompleted(success: success)
        }
        let work = Task {
            let result = await execute(source: source, wasInBackground: inBackground)
            finish(result.success && !Task.isCancelled)
        }
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                work.cancel()
                self?.flow.interruptBackgroundQuota()
                self?.record(.init(kind: "expired", source: source, at: Date()))
                finish(false)
            }
        }
    }
}

/// One flow instance serves UI, foreground and system background handlers, so
/// simultaneous requests use the same account coordination and persistence.
@MainActor
final class AppBackgroundRuntime {
    static let shared = AppBackgroundRuntime()
    let flow: CodexConnectionFlow
    let preferences: UserDefaults
    let coordinator: BackgroundQuotaRefresh
    private let enabled: Bool
    private let source: String

    private init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        flow = CodexConnectionUITestSupport.makeFlow()
        preferences = CodexConnectionUITestSupport.preferences
        let isolated = arguments.contains(where: { $0.hasPrefix("--t") || $0 == "--management-ui" })
        enabled = NSClassFromString("XCTestCase") == nil && (!isolated || arguments.contains("--t30-background-debug"))
        source = arguments.contains("--t30-background-debug") ? "debug" : "system"
        let directory = isolated || NSClassFromString("XCTestCase") != nil
            ? FileManager.default.temporaryDirectory.appendingPathComponent("T30-debug")
            : Self.applicationDirectory
        #else
        flow = CodexConnectionFlow.live()
        preferences = .standard
        enabled = true
        source = "system"
        let directory = Self.applicationDirectory
        #endif
        coordinator = BackgroundQuotaRefresh(flow: flow, journalURL: directory.appendingPathComponent("events.json"), enabled: enabled)
        #if DEBUG
        if source == "debug" {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("events.json"))
            // Each explicit debug launch starts a separate evidence session.
            coordinator.record(.init(kind: "debugSession", source: "debug", at: Date()))
        }
        #endif
    }

    private static var applicationDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackgroundRefresh")
    }

    func register() {
        guard enabled else { return }
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundQuotaRefresh.identifier, using: .main) { task in
            Task { @MainActor in self.coordinator.handle(task, source: self.source) }
        }
        coordinator.record(.init(kind: registered ? "registered" : "registrationFailed", source: "request", at: Date()))
        if registered { Task { await coordinator.scheduleIfNeeded() } }
    }

    #if DEBUG
    var debugSummary: String {
        guard source == "debug" else { return "" }
        let sessionStart = coordinator.events.lastIndex(where: { $0.kind == "debugSession" }) ?? 0
        let current = coordinator.events[sessionStart...]
        guard let event = current.last(where: { $0.kind == "finished" }), let result = event.result else { return "T30 waiting" }
        return "T30 \(event.source) background=\(event.wasInBackground == true) success=\(result.succeeded) failed=\(result.failed)"
    }
    #endif
}
