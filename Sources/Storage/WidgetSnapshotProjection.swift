import Foundation

/// Mapping lives in the App target. The extension needs only the display contract.
extension WidgetSnapshot {
    static func projecting(_ accounts: [ConnectedAccount]) -> WidgetSnapshot {
        // Pending deletion is already disconnected; never borrow another record's fields.
        guard let first = accounts.first(where: { $0.deletionPending != true }) else { return .empty }
        let quota = first.quotaSnapshot
        func window(_ input: QuotaWindowSnapshot) -> Window {
            let amount: Amount
            switch input.amount {
            case .unknown: amount = .unknown
            case .unlimited: amount = .unlimited
            case let .limited(value): amount = .limited(usedPercent: value.used)
            }
            return Window(amount: amount, resetsAt: input.resetsAt, observedAt: input.observedAt)
        }
        let state: State
        switch first.quotaState {
        case .notFetched: state = .notFetched
        case .notApplicable: state = .notApplicable
        case .available: state = .available
        }
        return WidgetSnapshot(schemaVersion: 1, account: Account(
            id: first.id, identity: first.verifiedEmail ?? first.remoteUserID ?? "Codex 账户",
            plan: first.subscription?.planType ?? quota?.planType, isDemo: first.isDemo, state: state,
            subscriptionObservedAt: first.subscription?.observedAt,
            quotaObservedAt: quota?.observedAt,
            weekly: quota.map { window($0.weekly) }, fiveHours: quota.map { window($0.fiveHours) }))
    }
}
