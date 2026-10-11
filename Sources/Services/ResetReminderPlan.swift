import Foundation
import CryptoKit

struct ResetReminderRequest: Equatable, Sendable {
    let identifier: String
    let accountID: UUID
    let window: QuotaWindow
    let resetsAt: Date
    let title: String
    let body: String
}

/// Pure projection of trusted observations. It neither queries quota nor sends
/// notifications; callers inject a separate, isolated notification destination.
enum ResetReminderPlan {
    static func requests(accounts: [ConnectedAccount], wantsReminders: Bool,
                         authorization: ResetReminderAuthorizationStatus,
                         now: Date) -> [ResetReminderRequest] {
        guard wantsReminders, authorization.permitsReminders,
              now.timeIntervalSince1970.isFinite else { return [] }

        return accounts.flatMap { account -> [ResetReminderRequest] in
            guard !account.isDemo, account.deletionPending != true,
                  account.quotaState == .available,
                  let snapshot = account.quotaSnapshot,
                  snapshot.accountID == account.id,
                  snapshot.provider == account.provider,
                  snapshot.product == account.product,
                  snapshot.scope == account.scope,
                  snapshot.generation == account.generation,
                  snapshot.observedAt.timeIntervalSince1970.isFinite,
                  let identity = identity(for: account) else { return [] }
            if let subscription = account.subscription {
                guard subscription.isValid,
                      subscription.planType == snapshot.planType,
                      subscription.observedAt >= snapshot.observedAt else { return [] }
            }

            return [(QuotaWindow.weekly, snapshot.weekly), (.fiveHours, snapshot.fiveHours)]
                .compactMap { expected, window in
                    guard window.window == expected, window.amount != .unknown,
                          window.observedAt == snapshot.observedAt,
                          let reset = window.resetsAt else { return nil }
                    let seconds = reset.timeIntervalSince1970
                    guard seconds.isFinite, (1...253_402_300_799).contains(seconds),
                          reset > now, reset > window.observedAt else { return nil }
                    let label = expected == .weekly ? "周额度" : "5 小时额度"
                    return ResetReminderRequest(
                        identifier: "quota-reset.v1.\(account.id.uuidString.lowercased()).\(bindingKey(account)).\(expected.rawValue).\(seconds)",
                        accountID: account.id, window: expected, resetsAt: reset,
                        title: "Codex · \(identity)", body: "\(label)预计重置，打开查看")
                }
        }
    }

    /// Connection renewal/generation and list position are not reminder identity.
    /// A verified scope change must not inherit the previous scope's processed round.
    private static func bindingKey(_ account: ConnectedAccount) -> String {
        let fields = [account.remoteUserID ?? "", account.scope.remoteAccountID,
                      account.scope.kind.rawValue]
        let data = Data(fields.map { "\($0.utf8.count):\($0)" }.joined().utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func identity(for account: ConnectedAccount) -> String? {
        [account.verifiedEmail, account.remoteUserID, account.scope.remoteAccountID]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }
    }
}
