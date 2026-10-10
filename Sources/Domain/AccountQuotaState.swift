/// No successful quota query has happened. This state carries no values or timestamps.
/// T11's independent quota-window model does not alter this stored state.
/// T12 will persist successful snapshots after a real query.
enum AccountQuotaState: String, Codable, Sendable {
    case notFetched
}
