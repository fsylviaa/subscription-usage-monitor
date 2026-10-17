import Foundation

/// Immutable projection: failure and reset crossing never replace an observation.
struct QuotaStyledInput: Equatable {
    struct Window: Identifiable, Equatable {
        /// `grokBot` is Cursor's second row (D-80), drawn exactly like Codex's five-hour row.
        enum Kind: String, Equatable { case weekly, fiveHours, monthly, grokBot }
        let kind: Kind
        let amount: QuotaCardAmount
        let resetsAt: Date?
        /// The primary window (weekly / monthly) uses the main colour scheme (D-77).
        var weekly: Bool { kind != .fiveHours && kind != .grokBot }
        var id: String { kind.rawValue }
        var title: String {
            switch kind { case .weekly: "每周"; case .fiveHours: "5 小时"; case .monthly: "本月"; case .grokBot: "Grok Bot" }
        }

        init(kind: Kind, amount: QuotaCardAmount, resetsAt: Date?) {
            self.kind = kind; self.amount = amount; self.resetsAt = resetsAt
        }
        init(weekly: Bool, amount: QuotaCardAmount, resetsAt: Date?) {
            self.init(kind: weekly ? .weekly : .fiveHours, amount: amount, resetsAt: resetsAt)
        }
    }
    var platform: QuotaPlatform = .codex
    let plan: String?
    let windows: [Window]
    let message: String?
    let lastSuccess: Date?

    init(account: WidgetSnapshot.Account?) {
        guard let account else {
            plan = nil; windows = []; message = "添加账户"; lastSuccess = nil; return
        }
        plan = account.plan; lastSuccess = account.quotaObservedAt; platform = account.resolvedPlatform
        if account.state == .notApplicable {
            windows = []; message = "无适用额度"
        } else if account.state == .notFetched {
            windows = []; message = account.failure == nil ? "尚未获取额度" : "刷新失败"
        } else {
            var values: [Window] = []
            if let week = account.weekly {
                values.append(.init(kind: platform == .cursor ? .monthly : .weekly,
                                    amount: QuotaCardAmount(week.amount), resetsAt: week.resetsAt))
            }
            if platform == .codex, let five = account.fiveHours, five.showsFiveHourLimit {
                values.append(.init(weekly: false, amount: QuotaCardAmount(five.amount), resetsAt: five.resetsAt))
            }
            if platform == .cursor, let grok = account.grokBot {
                values.append(.init(kind: .grokBot, amount: QuotaCardAmount(grok.amount), resetsAt: grok.resetsAt))
            }
            windows = values
            message = account.failure.map { $0 == .networkBlocked ? "网络不达标，无法更新" : "刷新失败" }
        }
    }

    func singleWindow(_ id: String) -> Self {
        .init(plan: plan, windows: windows.filter { $0.id == id }, message: message, lastSuccess: lastSuccess, platform: platform)
    }
    init(plan: String?, windows: [Window], message: String? = nil, lastSuccess: Date? = nil, platform: QuotaPlatform = .codex) {
        self.plan = plan; self.windows = windows; self.message = message; self.lastSuccess = lastSuccess
        self.platform = platform
    }
}

extension QuotaCardAmount {
    var nativeText: String {
        switch self {
        case .unknown: return "未知"
        case .unlimited: return "不限量"
        case .remaining:
            // Formatting never feeds geometry: bars keep the exact value (D-81).
            guard let wholeRemaining else { return "未知" }
            return "\(wholeRemaining)%"
        }
    }

    /// Card / widget / VoiceOver reading: plain half-up rounding, no edge cases (D-81).
    var wholeRemaining: Int? {
        guard case let .remaining(value) = self, remainingFraction != nil else { return nil }
        return Int(value.rounded(.toNearestOrAwayFromZero))
    }

    /// Detail list exact value, always two decimals, e.g. “75.43%”, “100.00%” (D-81).
    var preciseText: String? {
        guard case let .remaining(value) = self, remainingFraction != nil else { return nil }
        return value.formatted(.number.precision(.fractionLength(2)).rounded(rule: .toNearestOrAwayFromZero).grouping(.never)) + "%"
    }
}

enum NativeQuotaReset {
    static func text(_ date: Date?, now: Date) -> String {
        guard let date else { return "未提供重置时间" }
        guard date > now else { return "已到预计时间" }
        return "预计重置 · " + date.formatted(.dateTime.month().day().hour().minute())
    }
}
