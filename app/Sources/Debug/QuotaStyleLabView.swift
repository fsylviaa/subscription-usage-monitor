#if DEBUG
import SwiftUI

/// Launch-only validation surface. It creates no live runtime or persisted data.
struct QuotaStyleLabView: View {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("--t66-native-lab") }
    static func argument(_ flag: String) -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: flag), a.indices.contains(i + 1) else { return nil }
        return a[i + 1]
    }
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var index = Int(argument("--style-index") ?? "0") ?? 0
    @State private var dark = argument("--lab-theme") == "dark"
    @State private var large = argument("--lab-size") == "large"
    @State private var still = false
    @State private var alternate = false
    private let styles = QuotaCardStyle.allCases
    private var style: QuotaCardStyle { styles[min(max(index, 0), styles.count - 1)] }
    private var input: QuotaStyledInput {
        Self.fixture(scenario: Self.argument("--lab-scenario") ?? "normal", alternate: alternate)
    }
    static func fixture(scenario: String, alternate: Bool = false) -> QuotaStyledInput {
        QuotaStyledInput(account: fixtureAccount(scenario: scenario, alternate: alternate))
    }
    static func fixtureAccount(scenario: String, alternate: Bool = false) -> WidgetSnapshot.Account {
        let time = Date(timeIntervalSince1970: 1_791_590_400)
        var week: WidgetSnapshot.Amount = .limited(usedPercent: alternate ? 5.75 : 29.875)
        var five: WidgetSnapshot.Amount = .limited(usedPercent: alternate ? 87.2 : 66.67)
        if scenario == "endpoints" { week = .limited(usedPercent: 100); five = .limited(usedPercent: 0) }
        if scenario == "unknown" { week = .unknown; five = .unlimited }
        if scenario == "unlimited" { week = .unlimited; five = .unknown }
        let measured = scenario != "empty" && scenario != "first"
        let noFive = scenario == "weekly"
        return .init(id: UUID(), identity: "isolated@example.invalid",
            plan: scenario == "long" ? "Enterprise 超长套餐名称 · 团队专属订阅" : "Pro", isDemo: false,
            state: scenario == "empty" ? .notApplicable : scenario == "first" ? .notFetched : .available,
            subscriptionObservedAt: time, quotaObservedAt: measured ? time : nil,
            weekly: measured ? .init(amount: week, resetsAt: time.addingTimeInterval(86400 * 5), observedAt: time) : nil,
            fiveHours: measured ? .init(amount: noFive ? .unknown : five,
                resetsAt: noFive ? nil : time.addingTimeInterval(14400), observedAt: time,
                isApplicable: !noFive) : nil,
            failure: scenario == "failure" ? .refresh : nil)
    }
    var body: some View {
        VStack(spacing: 8) {
            Text("D-76 · 隔离原生验收").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("上一款") { index = (index + styles.count - 1) % styles.count }.accessibilityIdentifier("lab.previous")
                Spacer(); Text("\(index + 1)/\(styles.count) \(style.name)").font(.headline).accessibilityIdentifier("lab.style")
                Spacer(); Button("下一款") { index = (index + 1) % styles.count }.accessibilityIdentifier("lab.next")
            }.padding(.horizontal)
            HStack {
                Button(dark ? "切亮版" : "切暗版") { dark.toggle() }.accessibilityIdentifier("lab.theme")
                Button(large ? "正常字号" : "大字号") { large.toggle() }.accessibilityIdentifier("lab.size")
                Button("观察变化") { alternate.toggle() }.accessibilityIdentifier("lab.change")
                Button(still ? "恢复动态" : "静态检查") { still.toggle() }.accessibilityIdentifier("lab.motion")
            }.buttonStyle(.bordered).font(.caption)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("账户整卡").font(.caption)
                    QuotaStyledCard(style: style, input: input, now: Self.referenceTime)
                        .transaction { transaction in
                            if Self.argument("--lab-parent-animation") == "disabled" {
                                transaction.animation = nil; transaction.disablesAnimations = true
                            }
                        }
                    Text("详情单窗口（5 小时）").font(.caption)
                    QuotaStyledCard(style: style, input: input.singleWindow("fiveHours"), surface: .detail, now: Self.referenceTime)
                    Text("小号静态布局 · 原生渲染").font(.caption)
                    QuotaStyledCard(style: style, input: input, surface: .smallWidget, now: Self.referenceTime)
                        .frame(width: 158, height: 158).dynamicTypeSize(.large)
                    Text("中号静态布局 · 原生渲染").font(.caption)
                    QuotaStyledCard(style: style, input: input, surface: .mediumWidget, now: Self.referenceTime)
                        .frame(height: 158).dynamicTypeSize(.large)
                    Text("此处两尺寸为布局验收，桌面宿主尚未接入。数据仅在内存，不是平台查询。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(16).dynamicTypeSize(large ? .accessibility5 : .large)
            }
            // `--lab-anchor bottom` opens on the widget layouts for screenshots.
            .defaultScrollAnchor(Self.argument("--lab-anchor") == "bottom" ? .bottom : .top)
            .accessibilityIdentifier("lab.scroll")
        }
        .preferredColorScheme(dark ? .dark : .light)
        .environment(\.nativeQuotaStatic, still || UIAccessibility.isReduceMotionEnabled)
        .background(Color(uiColor: .systemGroupedBackground))
    }
    static let referenceTime = Date(timeIntervalSince1970: 1_791_590_400)
}
#endif
