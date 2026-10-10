import SwiftUI

/// Tokens and vectors from the project's read-only Figma source.
enum DashboardStyle {
    static let background = Color("DesignBg")
    static let card = Color("DesignCard")
    static let elevated = Color("DesignElevated")
    static let text = Color("DesignText")
    static let secondary = Color("DesignSecondary")
    static let track = Color("DesignTrack")
    static let accent = Color("DesignAccent")
    static let accentText = Color("DesignAccentText")
}

struct DesignIcon: View {
    let name: String
    var size: CGFloat = 20
    var body: some View {
        Image("Design" + name).resizable().scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct QuotaView: View {
    var accounts: [ConnectedAccount] = []
    var loading = false
    var loadFailed = false
    var canConnect = true
    var updatingID: UUID?
    var quotaFailure: String?
    var quotaFailureID: UUID?
    var failedAccountIDs: Set<UUID> = []
    var showDashboardFeedback = true
    var connect: () -> Void = {}
    var retry: (UUID) -> Void = { _ in }
    var closeFeedback: () -> Void = {}
    @ScaledMetric(relativeTo: .headline) private var titleSize = 18

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("订阅额度").font(.system(size: titleSize, weight: .semibold))
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("quota.title")
                Spacer(minLength: 12)
                Button { if let id = quotaFailureID { retry(id) } } label: {
                    DesignIcon(name: "Refresh").frame(width: 44, height: 44)
                }
                // T13 permits retrying a failed first fetch. Regular refresh is T25/T26.
                .disabled(quotaFailureID == nil || updatingID != nil)
                .accessibilityLabel("刷新").accessibilityIdentifier("quota.refresh")
                Button(action: connect) {
                    DesignIcon(name: "Link").frame(width: 44, height: 44)
                }
                .disabled(!canConnect).accessibilityLabel("连接 Codex")
                .accessibilityIdentifier("quota.toolbarConnect")
            }
            .buttonStyle(.plain)
            .padding(.leading, 16).padding(.trailing, 12).frame(minHeight: 48)

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadFailed {
                ContentUnavailableView("刷新失败", systemImage: "exclamationmark.circle")
            } else if accounts.isEmpty {
                ContentUnavailableView {
                    Label("未连接账户", systemImage: "link").accessibilityIdentifier("quota.empty")
                } actions: {
                    Button("连接 Codex", action: connect)
                        .buttonStyle(DashboardButtonStyle())
                        .accessibilityIdentifier("quota.connect")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        if showDashboardFeedback {
                            if updatingID != nil {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("正在更新").font(.subheadline)
                                    Spacer()
                                }
                                .padding(12).background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("quota.updating")
                            } else if let quotaFailure, let id = quotaFailureID {
                                HStack(spacing: 12) {
                                    Text(quotaFailure).font(.subheadline)
                                        .accessibilityIdentifier("quota.failure")
                                    Spacer(minLength: 0)
                                    Button("重试") { retry(id) }
                                        .font(.subheadline.weight(.semibold))
                                        .accessibilityIdentifier("quota.retry")
                                    Button(action: closeFeedback) {
                                        DesignIcon(name: "Close", size: 16).frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("关闭提示").accessibilityIdentifier("quota.closeFeedback")
                                }
                                .buttonStyle(.plain).padding(.leading, 12)
                                .background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        ForEach(accounts) { account in
                            QuotaAccountCard(account: account, updating: updatingID == account.id,
                                             failed: failedAccountIDs.contains(account.id) || quotaFailureID == account.id)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
                }
            }
        }
        .foregroundStyle(DashboardStyle.text)
        .background(DashboardStyle.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    static func amountText(_ amount: QuotaAmount) -> String {
        switch amount {
        case .unknown: "未知"
        case .unlimited: "不限量"
        case let .limited(value): "剩余 \(value.remaining.formatted(.number.precision(.fractionLength(0...2))))%"
        }
    }

    static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().hour().minute())
    }

    static func resetText(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let date else { return "未提供重置时间" }
        guard date > now else { return "已到预计时间" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        if date.timeIntervalSince(now) >= 86_400, days > 0 {
            return "\(days) 天后 \(date.formatted(.dateTime.hour().minute()))"
        }
        let minutes = max(1, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes < 60 { return "\(minutes) 分钟后" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) 小时后" : "\(hours) 小时 \(rest) 分后"
    }
}

private struct QuotaAccountCard: View {
    let account: ConnectedAccount
    let updating: Bool
    let failed: Bool
    @State private var expanded = false
    @ScaledMetric(relativeTo: .headline) private var titleSize = 17
    @ScaledMetric(relativeTo: .caption2) private var emailSize = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                DesignIcon(name: "Codex", size: 24.48)
                    .frame(width: 34, height: 34)
                    .background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 1) {
                    if account.quotaSnapshot != nil {
                        Button {
                            expanded.toggle()
                        } label: {
                            planTitle
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("quota.details")
                        .accessibilityValue(expanded ? "已展开" : "已收起")
                    } else {
                        planTitle
                    }
                    Text(account.verifiedEmail ?? account.remoteUserID ?? "Codex 账户")
                        .font(.system(size: emailSize)).foregroundStyle(DashboardStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true).privacySensitive()
                        .accessibilityIdentifier("quota.accountIdentity")
                }
                Spacer(minLength: 0)
            }
            if let snapshot = account.quotaSnapshot {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: 10) {
                        QuotaWindowView(value: snapshot.weekly, title: "每周", id: "weekly", now: context.date)
                        QuotaWindowView(value: snapshot.fiveHours, title: "5 小时", id: "fiveHours", now: context.date)
                    }
                }
                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Rectangle().fill(Color("DesignLine")).frame(height: 0.5)
                        Text("更新于 \(QuotaView.dateText(snapshot.observedAt))")
                            .font(.caption).foregroundStyle(DashboardStyle.secondary)
                            .accessibilityIdentifier("quota.updatedAt")
                    }
                }
            } else if account.quotaState == .notFetched {
                Text(updating ? "正在获取额度" : (failed ? "获取失败" : "尚未获取额度"))
                    .font(.caption).foregroundStyle(DashboardStyle.secondary)
                    .accessibilityIdentifier(updating || failed ? "quota.accountStatus" : "quota.notFetched")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardStyle.card, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quota.card")
    }

    private var planTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(account.subscription.map { "Codex · \($0.planType)" } ?? "Codex")
                .font(.system(size: titleSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("quota.plan")
            if account.quotaSnapshot != nil {
                DesignIcon(name: expanded ? "Up" : "Down", size: 14)
            }
        }
    }
}

private struct QuotaWindowView: View {
    let value: QuotaWindowSnapshot
    let title: String
    let id: String
    let now: Date
    @ScaledMetric(relativeTo: .caption) private var labelSize = 12
    @ScaledMetric(relativeTo: .caption2) private var resetSize = 11
    @ScaledMetric(relativeTo: .headline) private var amountSize = 18

    var body: some View {
        VStack(spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) { reset; Spacer(minLength: 6); amount }
                VStack(alignment: .leading, spacing: 6) {
                    reset
                    HStack { Spacer(); amount }
                }
            }
            if case let .limited(percentage) = value.amount {
                GeometryReader { geometry in
                    Capsule().fill(DashboardStyle.track)
                        .overlay(alignment: .leading) {
                            Capsule().fill(DashboardStyle.text)
                                .frame(width: geometry.size.width * percentage.used / 100)
                        }
                }
                .frame(height: 6)
                .accessibilityElement().accessibilityLabel("\(title)额度条")
                .accessibilityValue("已用 \(valueUsedText)，\(QuotaView.amountText(value.amount))")
                .accessibilityIdentifier("quota.\(id).bar")
            }
        }
    }

    private var reset: some View {
        HStack(spacing: 5) {
            Text(title).font(.system(size: labelSize, weight: .medium)).fixedSize()
            DesignIcon(name: "Clock", size: 11)
            Text(QuotaView.resetText(value.resetsAt, now: now))
                .font(.system(size: resetSize)).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(value.resetsAt.map { "预计重置于 \(QuotaView.dateText($0))" } ?? "未提供重置时间")
                .accessibilityIdentifier("quota.\(id).reset")
        }
        .foregroundStyle(DashboardStyle.secondary)
    }

    private var amount: some View {
        Group {
            if case let .limited(percentage) = value.amount {
                (Text("剩余 ").font(.system(size: resetSize)).foregroundColor(DashboardStyle.secondary)
                 + Text("\(percentage.remaining.formatted(.number.precision(.fractionLength(0...2))))%")
                    .font(.system(size: amountSize, weight: .semibold)))
            } else {
                Text(QuotaView.amountText(value.amount)).font(.system(size: labelSize, weight: .medium))
            }
        }
        .fixedSize().monospacedDigit().accessibilityIdentifier("quota.\(id).remaining")
    }
    private var valueUsedText: String {
        guard case let .limited(percentage) = value.amount else { return "未知" }
        return percentage.used.formatted(.number.precision(.fractionLength(0...2))) + "%"
    }
}

struct DashboardButtonStyle: ButtonStyle {
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(secondary ? DashboardStyle.text : DashboardStyle.accentText)
            .background(secondary ? DashboardStyle.elevated : DashboardStyle.accent,
                        in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
