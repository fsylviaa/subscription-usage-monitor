import SwiftUI
import WidgetKit

struct QuotaWidgetEntry: TimelineEntry {
    let date: Date
    let content: QuotaWidgetContent
    var appearance: String = "system"
    var cardStyle: QuotaCardStyle = .defaultStyle
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
        await AutomaticWidgetRefresh.refresh(accountID: configuration.account?.id)
        let entry = readEntry(accountID: configuration.account?.id)
        #if DEBUG
        WidgetSnapshotStore.traceValidation("timeline.return", detail: "family=\(context.family) remaining=\(entry.content.account?.weekly?.amount.remainingPercent ?? -1)")
        #endif
        // A reload opportunity now performs real work, rather than rereading a
        // permanently unchanged cache. This is an earliest request, not a timer.
        return Timeline(entries: Self.countdownEntries(entry), policy: .after(Date().addingTimeInterval(CoordinatedQuotaUpdater.interval)))
    }
    /// The same content re-dated so the reset countdown keeps moving without a
    /// reload (T121): every minute for an hour, then every 10 minutes to a day,
    /// in case the system grants the next reload late.
    static func countdownEntries(_ entry: QuotaWidgetEntry) -> [QuotaWidgetEntry] {
        let start = entry.date
        let minute = Calendar.current.dateInterval(of: .minute, for: start)?.end ?? start.addingTimeInterval(60)
        let dates = (0..<60).map { minute.addingTimeInterval(Double($0) * 60) }
            + (1...138).map { minute.addingTimeInterval(3_600 + Double($0) * 600) }
        return [entry] + dates.map { .init(date: $0, content: entry.content, appearance: entry.appearance, cardStyle: entry.cardStyle) }
    }
    private func readEntry(accountID: String?) -> QuotaWidgetEntry {
        let content = QuotaWidgetContent.read(from: .displayStore()).selecting(accountID: accountID)
        #if DEBUG
        WidgetSnapshotStore.traceValidation("provider.read", detail: "remaining=\(content.account?.weekly?.amount.remainingPercent ?? -1) unavailable=\(content == .unavailable)")
        #endif
        return .init(date: .now, content: content,
                     appearance: WidgetAppearance.effectiveValue(),
                     cardStyle: QuotaCardStylePreferences.effectiveValue())
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
        SmallQuotaWidgetView(content: entry.content, medium: family == .systemMedium, now: entry.date)
            .environment(\.colorScheme, scheme)
            .environment(\.quotaCardStyle, entry.cardStyle)
            .modifier(CompactWidgetChrome(style: entry.cardStyle, shape: ContainerRelativeShape()))
            .containerBackground(for: .widget) {
                CompactQuotaBackground(style: entry.cardStyle, widget: true).environment(\.colorScheme, scheme)
            }
            .widgetURL(entry.content.destinationURL)
    }
}
