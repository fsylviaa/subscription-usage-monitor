import SwiftUI
import WidgetKit

struct QuotaWidgetEntry: TimelineEntry {
    let date: Date
    let content: QuotaWidgetContent
}

struct QuotaWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaWidgetEntry {
        // No invented identity, quota, or success timestamp, even in the gallery.
        .init(date: .now, content: .snapshot(.empty))
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaWidgetEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaWidgetEntry>) -> Void) {
        let entry = readEntry()
        // This only rereads the App's published snapshot. iOS controls execution;
        // the extension never performs an independent quota or network query.
        completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(30 * 60))))
    }

    private func readEntry() -> QuotaWidgetEntry {
        .init(date: .now, content: .read(from: .appGroupStore()))
    }
}

@main
struct SubscriptionUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SubscriptionUsageQuota", provider: QuotaWidgetProvider()) { entry in
            SmallQuotaWidgetView(content: entry.content)
                .containerBackground(Color("DesignCard"), for: .widget)
        }
        .configurationDisplayName("订阅额度")
        .description("查看首个 Codex 账户的每周与 5 小时剩余额度。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
