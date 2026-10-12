import Foundation
import CryptoKit
import SwiftUI
import WidgetKit
import AppIntents

/// Only display data enters the view; timestamps stay in storage, not the card.
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

    /// The exact rendered entry determines the link, including configured widgets.
    var destinationURL: URL {
        if showsAddAccount { return Self.addAccountURL }
        guard case let .snapshot(snapshot) = self else { return URL(string: "subscriptionusage://quota")! }
        return snapshot.clickTarget
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
    static func effectiveValue() -> String {
        #if DEBUG
        let store = WidgetSnapshotStore.displayStore()
        if let url = try? store.resolvedURL(), url != (try? WidgetSnapshotStore.appGroupStore().resolvedURL()),
           let value = try? String(contentsOf: url.deletingLastPathComponent().appendingPathComponent("T37-appearance"), encoding: .utf8),
           ["light", "dark"].contains(value) { return value }
        #endif
        return defaults()?.string(forKey: key) ?? "system"
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
    private let store: WidgetSnapshotStore?
    init() { store = nil }
    init(store: WidgetSnapshotStore) { self.store = store }

    func entities(for identifiers: [String]) async throws -> [WidgetAccountEntity] {
        let options = try await suggestedEntities()
        #if DEBUG
        WidgetSnapshotStore.traceValidation("entity.resolve", detail: "requested=\(identifiers.count) missing=\(identifiers.filter { id in !options.contains { $0.id == id } }.count)")
        #endif
        return identifiers.compactMap { id in options.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [WidgetAccountEntity] {
        // App Intents can retain defaultQuery across isolated validation sessions.
        // Resolve the current publication at read time, just as the Provider does.
        [.first] + (try (store ?? .displayStore()).read()?.allAccounts ?? []).map(WidgetAccountEntity.init(account:))
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
                                if account.fiveHours?.showsFiveHourLimit == true {
                                    window("5 小时", value: account.fiveHours)
                                }
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


/// A local opaque target plus an identity fingerprint. Neither email nor a
/// credential is carried by the URL. Generations are deliberately excluded:
/// successful reconnection of the same email keeps the account's existing link.
enum WidgetQuotaRoute: Equatable {
    case addAccount
    case quota(accountID: UUID?, identityKey: String?)

    init?(url: URL) {
        guard url.scheme == "subscriptionusage", url.path.isEmpty,
              url.user == nil, url.password == nil, url.port == nil,
              url.fragment == nil else { return nil }
        if url.host == "add-account" { self = .addAccount; return }
        guard url.host == "quota" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let ids = items.filter { $0.name == "account" }
        let keys = items.filter { $0.name == "identity" }
        guard ids.count == 1, keys.count == 1, items.count == 2,
              let rawID = ids[0].value, let id = UUID(uuidString: rawID),
              let key = keys[0].value, key.count == 64,
              key.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            self = .quota(accountID: nil, identityKey: nil); return
        }
        self = .quota(accountID: id, identityKey: key)
    }

    static func identityKey(_ identity: String, isDemo: Bool) -> String {
        let normalized = identity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SHA256.hash(data: Data("codex:\(isDemo):\(normalized)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func url(accountID: UUID, identity: String, isDemo: Bool) -> URL {
        var url = URLComponents()
        url.scheme = "subscriptionusage"; url.host = "quota"
        url.queryItems = [URLQueryItem(name: "account", value: accountID.uuidString),
                          URLQueryItem(name: "identity", value: identityKey(identity, isDemo: isDemo))]
        return url.url!
    }
}
