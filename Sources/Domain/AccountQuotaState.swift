/// No successful quota query has happened. This state carries no values or timestamps.
/// T11 will add the independent quota-window model; T12 will persist successful snapshots.
enum AccountQuotaState: String, Codable, Sendable {
    case notFetched
}
