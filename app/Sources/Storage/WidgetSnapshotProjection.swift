import Foundation

/// Mapping lives in the App target. The extension needs only the display contract.
extension WidgetSnapshot {
    static func projecting(_ accounts: [ConnectedAccount], failures: [UUID: Failure] = [:]) -> WidgetSnapshot {
        let values = accounts.filter { $0.deletionPending != true }.compactMap { value -> Account? in
            guard var projected = projectAccount(value) else { return nil }
            projected.failure = failures[value.id]
            return projected
        }
        guard let first = values.first else { return .empty }
        return WidgetSnapshot(schemaVersion: 1, account: first, accounts: values)
    }

    private static func projectAccount(_ first: ConnectedAccount) -> Account? {
        // Pending deletion is already disconnected; never borrow another record's fields.
        let quota = first.quotaSnapshot
        func window(_ input: QuotaWindowSnapshot) -> Window {
            let amount: Amount
            switch input.amount {
            case .unknown: amount = .unknown
            case .unlimited: amount = .unlimited
            case let .limited(value): amount = .limited(usedPercent: value.used)
            }
            return Window(amount: amount, resetsAt: input.resetsAt, observedAt: input.observedAt,
                          isApplicable: input.isApplicable)
        }
        let state: State
        switch first.quotaState {
        case .notFetched: state = .notFetched
        case .notApplicable: state = .notApplicable
        case .available: state = .available
        }
        return Account(
            id: first.id, identity: first.identityText,
            plan: first.subscription?.planType ?? quota?.planType, isDemo: first.isDemo, state: state,
            subscriptionObservedAt: first.subscription?.observedAt,
            quotaObservedAt: first.isBalance ? first.balance?.observedAt : quota?.observedAt,
            weekly: quota.map { window($0.weekly) }, fiveHours: quota.map { window($0.fiveHours) },
            platform: first.platform,
            grokBot: first.platform == .cursor ? first.grokBot?.displayed.map(window) : nil,
            // Display needs only each currency's total (D-82).
            balance: first.isBalance ? first.balance?.amounts.map { BalanceAmount(currency: $0.currency, total: $0.total) } : nil)
    }
}
