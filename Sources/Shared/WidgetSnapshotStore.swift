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

    static func displayStore() -> Self {
        #if DEBUG
        if let root = try? sharedDirectory(),
           let text = try? String(contentsOf: root.appendingPathComponent("T35-validation-session"), encoding: .utf8),
           let session = UUID(uuidString: text) {
            return Self(fileURL: root.appendingPathComponent("T35-validation-\(session)/snapshot.json"))
        }
        #endif
        return .appGroupStore()
    }

    #if DEBUG
    /// Explicit developer-only desktop checks. Never replaces the production snapshot.
    static func validationStore(session: UUID) throws -> Self {
        Self(fileURL: try sharedDirectory().appendingPathComponent("T35-validation-\(session)/snapshot.json"))
    }

    static func setValidationSession(_ session: UUID?) throws {
        let root = try sharedDirectory()
        let marker = root.appendingPathComponent("T35-validation-session")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let session {
            try Data(session.uuidString.utf8).write(to: marker, options: .atomic)
        } else {
            let previous = (try? String(contentsOf: marker, encoding: .utf8)).flatMap(UUID.init(uuidString:))
            if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
            if let previous { try? FileManager.default.removeItem(at: root.appendingPathComponent("T35-validation-\(previous)")) }
        }
    }
    #endif

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
