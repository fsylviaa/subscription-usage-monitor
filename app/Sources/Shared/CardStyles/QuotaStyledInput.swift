import Foundation

/// Immutable projection: failure and reset crossing never replace an observation.
struct QuotaStyledInput: Equatable {
    struct Window: Identifiable, Equatable {
        let weekly: Bool
        let amount: QuotaCardAmount
        let resetsAt: Date?
        var id: String { weekly ? "weekly" : "fiveHours" }
        var title: String { weekly ? "每周" : "5 小时" }
    }
    let plan: String?
    let windows: [Window]
    let message: String?
    let lastSuccess: Date?

    init(account: WidgetSnapshot.Account?) {
        guard let account else {
            plan = nil; windows = []; message = "添加账户"; lastSuccess = nil; return
        }
        plan = account.plan; lastSuccess = account.quotaObservedAt
        if account.state == .notApplicable {
            windows = []; message = "无适用额度"
        } else if account.state == .notFetched {
            windows = []; message = account.failure == nil ? "尚未获取额度" : "刷新失败"
        } else {
            var values: [Window] = []
            if let week = account.weekly {
                values.append(.init(weekly: true, amount: QuotaCardAmount(week.amount), resetsAt: week.resetsAt))
            }
            if let five = account.fiveHours, five.showsFiveHourLimit {
                values.append(.init(weekly: false, amount: QuotaCardAmount(five.amount), resetsAt: five.resetsAt))
            }
            windows = values
            message = account.failure.map { $0 == .networkBlocked ? "网络不达标，无法更新" : "刷新失败" }
        }
    }

    func singleWindow(_ id: String) -> Self {
        .init(plan: plan, windows: windows.filter { $0.id == id }, message: message, lastSuccess: lastSuccess)
    }
    init(plan: String?, windows: [Window], message: String? = nil, lastSuccess: Date? = nil) {
        self.plan = plan; self.windows = windows; self.message = message; self.lastSuccess = lastSuccess
    }
}

extension QuotaCardAmount {
    var nativeText: String {
        switch self {
        case .unknown: return "未知"
        case .unlimited: return "不限量"
        case let .remaining(value):
            guard remainingFraction != nil else { return "未知" }
            // Formatting never feeds geometry. Preserve meaningful input decimals.
            return value.formatted(.number.precision(.fractionLength(0...6))) + "%"
        }
    }
}

enum NativeQuotaReset {
    static func text(_ date: Date?, now: Date) -> String {
        guard let date else { return "未提供重置时间" }
        guard date > now else { return "已到预计时间" }
        return "预计重置 · " + date.formatted(.dateTime.month().day().hour().minute())
    }
}
