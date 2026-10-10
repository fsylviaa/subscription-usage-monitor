import Foundation

/// App writes; extensions only read. An unavailable group is an error, never a
/// successful fallback to the App's private directory or a fabricated empty list.
struct WidgetSnapshotStore: Sendable {
    static let appGroupIdentifier = "group.com.iceflying.SubscriptionUsage"
    static let filename = "first-account.json"
    private static let maximumBytes = 65_536

    enum StoreError: Error, Equatable {
        case unavailableContainer, unsupportedSchema, invalidSnapshot, oversizedSnapshot
    }

    private let isolatedURL: URL?
    init(fileURL: URL) { isolatedURL = fileURL }
    private init() { isolatedURL = nil }
    static func appGroupStore() -> Self { Self() }

    static func sharedDirectory() throws -> URL {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw StoreError.unavailableContainer
        }
        return root.appendingPathComponent("Widget", isDirectory: true)
    }

    func resolvedURL() throws -> URL {
        if let isolatedURL { return isolatedURL }
        return try Self.sharedDirectory().appendingPathComponent(Self.filename)
    }

    /// nil means no publication yet; corrupt/unreadable files remain explicit errors.
    func read() throws -> WidgetSnapshot? {
        let url = try resolvedURL()
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return nil }
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard data.count <= Self.maximumBytes else { throw StoreError.oversizedSnapshot }
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        try snapshot.validate()
        return snapshot
    }

    func write(_ snapshot: WidgetSnapshot) throws {
        try snapshot.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= Self.maximumBytes else { throw StoreError.oversizedSnapshot }
        let url = try resolvedURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove() throws {
        do { try FileManager.default.removeItem(at: resolvedURL()) }
        catch CocoaError.fileNoSuchFile { }
    }
}

/// Selection files contain local display IDs only. Different configured numbers
/// have independent files. A new list revision invalidates old selections safely,
/// even when a tap from a stale widget races a reorder or deletion in the App.
extension WidgetSnapshotStore {
    private struct Selection: Codable {
        let revision: UUID?
        let accountID: UUID
    }

    private func selectionURL(number: Int) throws -> URL {
        try resolvedURL().deletingLastPathComponent()
            .appendingPathComponent("selection-\(number).json")
    }

    func selectedAccount(in snapshot: WidgetSnapshot, number: Int) -> WidgetSnapshot.Account? {
        guard let data = try? Data(contentsOf: selectionURL(number: number)),
              let selected = try? JSONDecoder().decode(Selection.self, from: data),
              selected.revision == snapshot.listRevision,
              let account = snapshot.allAccounts.first(where: { $0.id == selected.accountID }) else {
            return snapshot.account
        }
        return account
    }

    func switchAccount(number: Int, displayedID: UUID, revision: UUID?, direction: Int) throws {
        guard let snapshot = try read(), snapshot.listRevision == revision, snapshot.allAccounts.count > 1,
              let index = snapshot.allAccounts.firstIndex(where: { $0.id == displayedID }) else { return }
        let accounts = snapshot.allAccounts
        let target = accounts[(index + (direction < 0 ? -1 : 1) + accounts.count) % accounts.count]
        let data = try JSONEncoder().encode(Selection(revision: snapshot.listRevision, accountID: target.id))
        try data.write(to: selectionURL(number: number), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
