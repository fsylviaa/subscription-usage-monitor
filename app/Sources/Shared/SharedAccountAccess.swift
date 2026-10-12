import Foundation
import Darwin
import WidgetKit

/// A separate, stable lock file survives atomic replacement of the JSON file.
/// Nonblocking acquisition: a suspended process must never stall the other one.
final class SharedFileLease: @unchecked Sendable {
    enum LockError: Error { case busy, unavailable }
    private let descriptor: Int32

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw LockError.unavailable }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw LockError.busy
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

/// Foreground changes still request updates immediately; one final request is
/// coalesced when the App actually enters background (WWDC26 WidgetKit guidance).
final class WidgetPublicationRequests: @unchecked Sendable {
    static let shared = WidgetPublicationRequests()
    private let lock = NSLock()
    private var pending = false
    func changed() {
        lock.lock(); pending = true; lock.unlock()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetAppearance.kind)
    }
    func enteredBackground() {
        lock.lock(); let reload = pending; pending = false; lock.unlock()
        if reload { WidgetCenter.shared.reloadTimelines(ofKind: WidgetAppearance.kind) }
    }
}

/// A bounded ownership record, not an OS lock held over network awaits. A
/// suspended/crashed App cannot indefinitely block an independently running widget.
final class SharedQueryLease: @unchecked Sendable {
    private struct Record: Codable {
        let owner: UUID
        let expires: Date
    }
    private let url: URL
    private let owner = UUID()
    init(url: URL, at now: Date = Date()) throws {
        self.url = url
        let lock = try SharedFileLease(url: url.appendingPathExtension("guard"))
        defer { withExtendedLifetime(lock) {} }
        if let record = try Self.read(url), record.expires > now { throw SharedFileLease.LockError.busy }
        try JSONEncoder().encode(Record(owner: owner, expires: now.addingTimeInterval(90)))
            .write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func validate(at now: Date = Date()) throws {
        // Atomic JSON replacement means readers never observe a partial record.
        guard let record = try Self.read(url), record.owner == owner, record.expires > now else {
            throw CancellationError()
        }
    }
    private static func read(_ url: URL) throws -> Record? {
        do { return try JSONDecoder().decode(Record.self, from: Data(contentsOf: url)) }
        catch CocoaError.fileReadNoSuchFile { return nil }
    }
    deinit {
        // Only our own claim can be removed. If temporarily busy, its finite
        // lifetime still allows recovery; never remove another process's claim.
        if let lock = try? SharedFileLease(url: url.appendingPathExtension("guard")) {
            defer { withExtendedLifetime(lock) {} }
            if let record = try? Self.read(url), record.owner == owner { try? FileManager.default.removeItem(at: url) }
        }
    }
}
