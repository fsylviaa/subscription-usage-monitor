import Foundation

protocol CodexLoginTransactionStoring: Sendable {
    func save(_ authorization: CodexDeviceAuthorization) async throws
    func remove(transactionID: UUID) async throws
}

/// One pending connection, separate from every established credential. The stable slot
/// retains the original deadline across process termination for T10's recovery work.
actor CodexLoginTransactionStore: CodexLoginTransactionStoring {
    private let vault: CredentialVault
    private let entry = CredentialVault.Entry.loginTransaction(
        UUID(uuidString: "2BCEFFDE-7DC2-4F6A-89B0-020023689458")!
    )

    init(vault: CredentialVault = .applicationVault()) {
        self.vault = vault
    }

    func save(_ authorization: CodexDeviceAuthorization) async throws {
        let data = try JSONEncoder().encode(authorization)
        try await vault.save(CredentialPayload(data: data), for: entry)
    }

    func remove(transactionID: UUID) async throws {
        guard let payload = try await vault.load(for: entry) else { return }
        let current = try JSONDecoder().decode(CodexDeviceAuthorization.self, from: payload.data)
        guard current.transactionID == transactionID else { return }
        try await vault.remove(ifMatching: payload, for: entry)
    }
}
