import Foundation

protocol CodexLoginTransactionStoring: Sendable {
    func save(_ authorization: CodexDeviceAuthorization) async throws
    func load() async throws -> CodexDeviceAuthorization?
    func cancel(transactionID: UUID) async throws
    func loadCancelledTransactionID() async throws -> UUID?
    func discardInvalidRecord() async throws
    func remove(transactionID: UUID) async throws
}

extension CodexLoginTransactionStoring {
    func load() async throws -> CodexDeviceAuthorization? { nil }
    func cancel(transactionID: UUID) async throws { try await remove(transactionID: transactionID) }
    func loadCancelledTransactionID() async throws -> UUID? { nil }
    func discardInvalidRecord() async throws { }
}

/// One pending connection, separate from every established credential. The stable slot
/// retains the original deadline across process termination. Cancellation replaces
/// the authorization with an ID-only tombstone before intermediate secrets are removed.
actor CodexLoginTransactionStore: CodexLoginTransactionStoring {
    private let vault: CredentialVault
    private let entry = CredentialVault.Entry.loginTransaction(
        UUID(uuidString: "2BCEFFDE-7DC2-4F6A-89B0-020023689458")!
    )

    init(vault: CredentialVault = .applicationVault()) {
        self.vault = vault
    }

    func save(_ authorization: CodexDeviceAuthorization) async throws {
        try Task.checkCancellation()
        let current = try await vault.load(for: entry)
        if let current, case let .cancelled(id) = try decode(current), id == authorization.transactionID {
            throw CancellationError()
        }
        let data = try JSONEncoder().encode(authorization)
        try Task.checkCancellation()
        guard try await vault.replace(ifMatching: current, with: CredentialPayload(data: data), for: entry) else {
            // Cancellation or a newer transaction won the slot while preparing
            // this write; do not overwrite it with a late authorization response.
            throw CancellationError()
        }
    }

    func load() async throws -> CodexDeviceAuthorization? {
        guard let payload = try await vault.load(for: entry) else { return nil }
        switch try decode(payload) {
        case let .authorization(authorization): return authorization
        case .cancelled: return nil
        }
    }

    func loadCancelledTransactionID() async throws -> UUID? {
        guard let payload = try await vault.load(for: entry) else { return nil }
        if case let .cancelled(id) = try decode(payload) { return id }
        return nil
    }

    func cancel(transactionID: UUID) async throws {
        let cancelled = CancellationRecord(version: 1, cancelledTransactionID: transactionID)
        let replacement = CredentialPayload(data: try JSONEncoder().encode(cancelled))
        while true {
            let payload = try await vault.load(for: entry)
            if let payload {
                let current = try decode(payload)
                guard current.transactionID == transactionID else { return }
                if case .cancelled = current { return }
            }
            // Persist even before an in-flight initial save has created the slot.
            // Its conditional write will then observe cancellation and stop.
            if try await vault.replace(ifMatching: payload, with: replacement, for: entry) { return }
            // Another write raced the cancellation. Recheck the exact ID before
            // retrying so that a replacement authorization is never cancelled.
        }
    }

    /// Discard only the exact malformed fixed-slot package inspected here. A
    /// decodable authorization or cancellation written meanwhile is preserved.
    func discardInvalidRecord() async throws {
        guard let payload = try await vault.load(for: entry) else { return }
        do { _ = try decode(payload) }
        catch {
            try await vault.remove(ifMatching: payload, for: entry)
        }
    }

    func remove(transactionID: UUID) async throws {
        guard let payload = try await vault.load(for: entry) else { return }
        guard try decode(payload).transactionID == transactionID else { return }
        try await vault.remove(ifMatching: payload, for: entry)
    }

    private struct CancellationRecord: Codable {
        let version: Int
        let cancelledTransactionID: UUID
    }

    private enum Record {
        case authorization(CodexDeviceAuthorization)
        case cancelled(UUID)
        var transactionID: UUID {
            switch self {
            case let .authorization(value): value.transactionID
            case let .cancelled(id): id
            }
        }
    }

    private func decode(_ payload: CredentialPayload) throws -> Record {
        if let cancelled = try? JSONDecoder().decode(CancellationRecord.self, from: payload.data) {
            guard cancelled.version == 1 else { throw CodexLoginError.failed }
            return .cancelled(cancelled.cancelledTransactionID)
        }
        guard let authorization = try? JSONDecoder().decode(CodexDeviceAuthorization.self, from: payload.data) else {
            // Decoder diagnostics must never expose a persisted secret.
            throw CodexLoginError.failed
        }
        return .authorization(authorization)
    }
}
