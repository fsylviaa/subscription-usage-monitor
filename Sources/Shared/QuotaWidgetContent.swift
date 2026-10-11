import Foundation
import SwiftUI
import WidgetKit
import AppIntents

/// Only display data enters the extension; timestamps stay in storage, not the card.
enum QuotaWidgetContent: Equatable, Sendable {
    case snapshot(WidgetSnapshot)
    case notPublished
    case unavailable

    static func read(from store: WidgetSnapshotStore) -> Self {
        do {
            guard let snapshot = try store.read() else { return .notPublished }
            return .snapshot(snapshot)
        } catch { return .unavailable }
    }

    var account: WidgetSnapshot.Account? {
        guard case let .snapshot(snapshot) = self else { return nil }
        return snapshot.account
    }

    var showsAddAccount: Bool {
        switch self {
        case .notPublished: true
        case let .snapshot(snapshot): snapshot.account == nil
        case .unavailable: false
        }
    }

    var message: String? {
        switch self {
        case .notPublished: "添加账户"
        case .unavailable: "刷新失败"
        case let .snapshot(snapshot):
            snapshot.account.flatMap { $0.failure?.message(hasFetched: $0.state != .notFetched) } ?? snapshot.emptyMessage
        }
    }

    static let addAccountURL = URL(string: "subscriptionusage://add-account")!

    static func isAddAccountURL(_ url: URL) -> Bool {
        url.scheme == "subscriptionusage" && url.host == "add-account" && url.path.isEmpty
    }

    static func compactIdentity(_ identity: String) -> String {
        guard let at = identity.lastIndex(of: "@"), at != identity.startIndex else { return identity }
        return String(identity[..<at])
    }

    static func amountText(_ amount: WidgetSnapshot.Amount) -> String {
        switch amount {
        case .unknown: "未知"
        case .unlimited: "不限量"
        case let .limited(used): "剩余 \((100 - used).formatted(.number.precision(.fractionLength(0...2))))%"
        }
    }

    static func usedFraction(_ amount: WidgetSnapshot.Amount) -> Double? {
        guard case let .limited(used) = amount else { return nil }
        return used / 100
    }
}

/// App publishes its preference; widgets resolve 'system' against their own context.
enum WidgetAppearance {
    static let key = "widget.appearance"
    static let kind = "SubscriptionUsageQuota"
    static func defaults() -> UserDefaults? {
        UserDefaults(suiteName: WidgetSnapshotStore.appGroupIdentifier)
    }
    static func colorScheme(_ value: String) -> ColorScheme? {
        value == "dark" ? .dark : value == "light" ? .light : nil
    }
    static func publish(_ value: String, to defaults: UserDefaults?, reload: () -> Void) {
        guard let defaults else { return }
        let normalized = ["light", "dark"].contains(value) ? value : "system"
        guard defaults.string(forKey: key) != normalized else { return }
        defaults.set(normalized, forKey: key)
        reload()
    }
}

/// The system stores this choice separately for each widget instance.
/// A stable sentinel keeps the default following the list, instead of pinning
/// whichever account happened to be first when the widget was added.
struct WidgetAccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "账户"
    static let defaultQuery = WidgetAccountQuery()
    static let firstID = "first-account"
    static let first = WidgetAccountEntity(id: firstID, identity: "跟随列表首个账户", detail: "")

    let id: String
    let identity: String
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(identity)", subtitle: "\(detail)")
    }

    init(id: String, identity: String, detail: String) {
        self.id = id
        self.identity = identity
        self.detail = detail
    }

    init(account: WidgetSnapshot.Account) {
        id = account.id.uuidString
        identity = (account.isDemo ? "演示 · " : "") + account.identity
        detail = account.plan.map { "Codex · \($0)" } ?? "Codex"
    }
}

struct WidgetAccountQuery: EntityQuery {
    private let store: WidgetSnapshotStore
    init() { store = .displayStore() }
    init(store: WidgetSnapshotStore) { self.store = store }

    func entities(for identifiers: [String]) async throws -> [WidgetAccountEntity] {
        let options = try await suggestedEntities()
        return identifiers.compactMap { id in options.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [WidgetAccountEntity] {
        [.first] + (try store.read()?.allAccounts ?? []).map(WidgetAccountEntity.init(account:))
    }

    func defaultResult() async -> WidgetAccountEntity? { .first }
}

struct QuotaWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "订阅额度"
    static let description = IntentDescription("选择这个组件显示的账户；未选择时跟随列表首个账户。")
    @Parameter(title: "显示账户") var account: WidgetAccountEntity?
}

extension QuotaWidgetContent {
    /// Always resolve against the current trusted publication, never against
    /// cached entity labels or a former numbered selection file.
    func selecting(accountID: String?) -> Self {
        guard case let .snapshot(snapshot) = self else { return self }
        let selected = snapshot.allAccounts.first { $0.id.uuidString == accountID } ?? snapshot.account
        return .snapshot(.init(schemaVersion: 1, account: selected))
    }
}

/// Shared with isolated rendering checks. Same hierarchy and tokens as the App card.
struct SmallQuotaWidgetView: View {
    let content: QuotaWidgetContent
    var medium = false

    var body: some View {
        Group {
            if content.showsAddAccount {
                Text("添加账户")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: medium ? 12 : (content.account?.failure == nil ? 10 : 5)) {
                    if let account = content.account {
                        HStack(spacing: 7) {
                            Image("DesignCodex").resizable().renderingMode(.template)
                                .frame(width: medium ? 23 : 20, height: medium ? 23 : 20)
                                .frame(width: medium ? 32 : 28, height: medium ? 32 : 28)
                                .background(Color("DesignElevated"), in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.plan.map { "Codex · \($0)" } ?? "Codex")
                                    .font(.system(size: medium ? 16 : 14, weight: .semibold))
                                HStack(spacing: 2) {
                                    Text((account.isDemo ? "演示 · " : "") + QuotaWidgetContent.compactIdentity(account.identity))
                                        .font(.system(size: 11)).foregroundStyle(Color("DesignSecondary"))
                                        .truncationMode(.tail).privacySensitive()
                                    Spacer(minLength: 0)

                                }
                            }
                        }
                        if account.state == .available {
                            VStack(spacing: medium ? 12 : (account.failure == nil ? 10 : 6)) {
                                window("每周", value: account.weekly)
                                window("5 小时", value: account.fiveHours)
                            }
                        }
                    }
                    if let message = content.message {
                        Text(message).font(.system(size: 12)).foregroundStyle(Color("DesignSecondary"))
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(Color("DesignText"))
        .padding(medium ? 16 : 12)
    }

    private func window(_ title: String, value: WidgetSnapshot.Window?) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color("DesignSecondary")).fixedSize()
                Spacer(minLength: 0)
                if case let .limited(used) = value?.amount {
                    (Text("剩余 ").font(.system(size: 11)).foregroundColor(Color("DesignSecondary"))
                     + Text("\((100 - used).formatted(.number.precision(.fractionLength(0...2))))%")
                        .font(.system(size: medium ? 18 : 16, weight: .semibold)))
                        .monospacedDigit().layoutPriority(1)
                } else {
                    Text(QuotaWidgetContent.amountText(value?.amount ?? .unknown))
                        .font(.system(size: 12, weight: .medium))
                }
            }
            if let fraction = QuotaWidgetContent.usedFraction(value?.amount ?? .unknown) {
                GeometryReader { geometry in
                    Capsule().fill(Color("DesignTrack"))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color("DesignText"))
                                .frame(width: geometry.size.width * fraction)
                        }
                }
                .frame(height: 6)
                .accessibilityLabel("\(title)额度条")
                .accessibilityValue("已用 \((fraction * 100).formatted(.number.precision(.fractionLength(0...2))))%，\(QuotaWidgetContent.amountText(value?.amount ?? .unknown))")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
