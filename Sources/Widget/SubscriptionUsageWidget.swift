import SwiftUI
import WidgetKit

struct QuotaWidgetEntry: TimelineEntry {
    let date: Date
    let content: QuotaWidgetContent
    var appearance: String = "system"
    var number = 1
    var accountCount = 0
    var listRevision: UUID? = nil
}

struct QuotaWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaWidgetEntry {
        .init(date: .now, content: .snapshot(.empty))
    }
    func snapshot(for configuration: QuotaWidgetConfiguration, in context: Context) async -> QuotaWidgetEntry {
        readEntry(number: configuration.number)
    }
    func timeline(for configuration: QuotaWidgetConfiguration, in context: Context) async -> Timeline<QuotaWidgetEntry> {
        let entry = readEntry(number: configuration.number)
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(30 * 60)))
    }
    private func readEntry(number: Int) -> QuotaWidgetEntry {
        let store = WidgetSnapshotStore.appGroupStore()
        let content = QuotaWidgetContent.read(from: store)
        var selected = content
        var count = 0
        var revision: UUID?
        if case let .snapshot(snapshot) = content {
            count = snapshot.allAccounts.count
            revision = snapshot.listRevision
            selected = .snapshot(.init(schemaVersion: 1, account: store.selectedAccount(in: snapshot, number: number)))
        }
        return .init(date: .now, content: selected,
                     appearance: WidgetAppearance.defaults()?.string(forKey: WidgetAppearance.key) ?? "system",
                     number: number, accountCount: count, listRevision: revision)
    }
}

@main
struct SubscriptionUsageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetAppearance.kind, intent: QuotaWidgetConfiguration.self, provider: QuotaWidgetProvider()) { entry in
            QuotaWidgetSurface(entry: entry)
        }
        .configurationDisplayName("订阅额度")
        .description("查看账户额度；多个组件可设置不同编号，独立切换账户。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct QuotaWidgetSurface: View {
    let entry: QuotaWidgetEntry
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.widgetFamily) private var family
    private var scheme: ColorScheme { WidgetAppearance.colorScheme(entry.appearance) ?? systemScheme }
    var body: some View {
        SmallQuotaWidgetView(content: entry.content, medium: family == .systemMedium,
                             number: entry.number, accountCount: entry.accountCount, listRevision: entry.listRevision)
            .environment(\.colorScheme, scheme)
            .containerBackground(for: .widget) {
                Color("DesignCard").environment(\.colorScheme, scheme)
            }
            .widgetURL(entry.content.showsAddAccount ? QuotaWidgetContent.addAccountURL : nil)
    }
}
