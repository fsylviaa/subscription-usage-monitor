/// A successful quota is recorded only together with a persisted, known snapshot.
enum AccountQuotaState: String, Codable, Sendable {
    case notFetched
    case available
}
