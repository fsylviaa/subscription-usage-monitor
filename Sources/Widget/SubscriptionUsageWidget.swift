import SwiftUI
import WidgetKit

struct QuotaWidgetEntry: TimelineEntry {
    let date: Date
    let content: QuotaWidgetContent
    var appearance: String = "system"
}

struct QuotaWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaWidgetEntry {
        .init(date: .now, content: .snapshot(.empty))
    }
    func snapshot(for configuration: QuotaWidgetConfiguration, in context: Context) async -> QuotaWidgetEntry {
        readEntry(accountID: configuration.account?.id)
    }
    func timeline(for configuration: QuotaWidgetConfiguration, in context: Context) async -> Timeline<QuotaWidgetEntry> {
        #if DEBUG
        WidgetSnapshotStore.traceValidation("timeline.begin", detail: "family=\(context.family)")
        #endif
        let entry = readEntry(accountID: configuration.account?.id)
        #if DEBUG
        WidgetSnapshotStore.traceValidation("timeline.return", detail: "family=\(context.family) remaining=\(entry.content.account?.weekly?.amount.remainingPercent ?? -1)")
        #endif
        // This extension only reads the App's publication. A timer would reread
        // the same cache and consume reload budget without fetching new data.
        // AccountStore requests a timeline when visible data or membership changes.
        return Timeline(entries: [entry], policy: .never)
    }
    private func readEntry(accountID: String?) -> QuotaWidgetEntry {
        let content = QuotaWidgetContent.read(from: .displayStore()).selecting(accountID: accountID)
        #if DEBUG
        WidgetSnapshotStore.traceValidation("provider.read", detail: "remaining=\(content.account?.weekly?.amount.remainingPercent ?? -1) unavailable=\(content == .unavailable)")
        #endif
        return .init(date: .now, content: content,
                     appearance: WidgetAppearance.defaults()?.string(forKey: WidgetAppearance.key) ?? "system")
    }
}

@main
struct SubscriptionUsageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetAppearance.kind, intent: QuotaWidgetConfiguration.self, provider: QuotaWidgetProvider()) { entry in
            QuotaWidgetSurface(entry: entry)
        }
        .configurationDisplayName("订阅额度")
        .description("长按编辑小组件，为每个组件选择显示账户。")
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
        SmallQuotaWidgetView(content: entry.content, medium: family == .systemMedium)
            .environment(\.colorScheme, scheme)
            .containerBackground(for: .widget) {
                Color("DesignCard").environment(\.colorScheme, scheme)
            }
            .widgetURL(entry.content.showsAddAccount ? QuotaWidgetContent.addAccountURL : nil)
    }
}
