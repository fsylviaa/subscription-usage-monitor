import SwiftUI

/// Shared tutorial. Navigation never performs a system widget operation.
struct WidgetTutorialView: View {
    var close: () -> Void
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    DesignIcon(name: "Close", size: 18).frame(width: 44, height: 44)
                }
                .accessibilityLabel("关闭教程")
                .accessibilityIdentifier("tutorial.close")
                Spacer(minLength: 0)
                Text("添加小组件").font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
            .padding(.horizontal, 8).padding(.top, 8)

            TabView(selection: $step) {
                ForEach(0..<2) { page in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            WidgetOperationIllustration(page: page, active: step == page)
                                .frame(maxWidth: .infinity)
                                .padding(24)
                                .background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 26))

                            Text(page == 0
                                 ? "长按主屏幕，然后添加 Token 仪表盘。"
                                 : "长按小组件，选择要显示的账号")
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("tutorial.instructions.\(page)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                    .clipped()
                    .tag(page)
                    .accessibilityHidden(step != page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier("tutorial.pages")

            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Capsule().fill(step == 1 ? DashboardStyle.track : DashboardStyle.text)
                        .frame(width: step == 1 ? 6 : 18, height: 6)
                    Capsule().fill(step == 1 ? DashboardStyle.text : DashboardStyle.track)
                        .frame(width: step == 1 ? 18 : 6, height: 6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(step == 1 ? "第 2 步，共 2 步" : "第 1 步，共 2 步")
                .accessibilityIdentifier("tutorial.step")
                Button(step == 1 ? "完成" : "继续") {
                    if step == 1 { close() } else { step = 1 }
                }
                .buttonStyle(DashboardButtonStyle())
                .accessibilityIdentifier("tutorial.next")
            }
            .padding(16)
        }
        .foregroundStyle(DashboardStyle.text)
        .background(DashboardStyle.background)
        .buttonStyle(.plain)
    }

}

/// A short demonstration inside a phone outline, never an interactive replica.
private struct WidgetOperationIllustration: View {
    let page: Int
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var frame = 0
    @ScaledMetric(relativeTo: .subheadline) private var contentHeight = 240

    private var count: Int { page == 0 ? 5 : 4 }
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
    }
    private var operation: String {
        page == 0 ? "长按主屏幕，编辑，添加小组件，搜索\(appName)，选择小号或中号，添加"
                  : "长按小组件，编辑小组件，显示账户，选择账号"
    }

    var body: some View {
        Group {
            if reduceMotion {
                VStack(spacing: 18) {
                    ForEach(0..<count, id: \.self) { index in phone(index, moving: false) }
                }
            } else {
                phone(frame, moving: true)
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(operation)
        .accessibilityValue(reduceMotion ? "静态关键画面" : "画面 \(frame + 1)，共 \(count) 个")
        .accessibilityIdentifier("tutorial.demo.\(page)")
        .task(id: "\(active)-\(reduceMotion)-\(scenePhase)") {
            guard active, !reduceMotion, scenePhase == .active else { return }
            frame = 0
            // Play once on each visit, then retain the outcome. Navigation is independent.
            for next in 1..<count {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) { frame = next }
            }
        }
    }

    private func phone(_ index: Int, moving: Bool) -> some View {
        VStack(spacing: 16) {
            Capsule().fill(DashboardStyle.text).frame(width: 48, height: 5)
            Group {
                if page == 0 { adding(index, moving: moving) }
                else { choosing(index, moving: moving) }
            }
            .id(index)
            .transition(.opacity)
            .frame(maxWidth: .infinity, minHeight: moving ? contentHeight : 190,
                   maxHeight: moving ? contentHeight : nil)
            Capsule().fill(DashboardStyle.secondary).frame(width: 62, height: 4)
        }
        .font(.subheadline)
        .padding(18)
        .frame(maxWidth: 280)
        .background(DashboardStyle.background, in: RoundedRectangle(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(DashboardStyle.track, lineWidth: 2))
    }

    @ViewBuilder
    private func adding(_ index: Int, moving: Bool) -> some View {
        switch index {
        case 0:
            VStack(spacing: 24) {
                icons
                HStack { Spacer(); touch(moving: moving) }
            }
        case 1:
            VStack(alignment: .leading, spacing: 18) {
                row("编辑", icon: "hand.point.up.left.fill")
                row("添加小组件", icon: "plus")
                icons
            }
        case 2:
            VStack(spacing: 18) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text(appName).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.padding(10).background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 10))
                row(appName, icon: "square.grid.2x2")
            }
        case 3:
            VStack(spacing: 16) {
                Text(appName).fontWeight(.semibold)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) { size("小号", medium: false); size("中号", medium: true) }
                    VStack(spacing: 10) { size("小号", medium: false); size("中号", medium: true) }
                }
                action("添加小组件")
            }
        default:
            VStack(spacing: 18) {
                HStack { Spacer(); Text("完成").fontWeight(.semibold) }
                widget
                icons
            }
        }
    }

    @ViewBuilder
    private func choosing(_ index: Int, moving: Bool) -> some View {
        switch index {
        case 0:
            VStack(spacing: 18) {
                widget
                HStack { Spacer(); touch(moving: moving) }
            }
        case 1:
            VStack(spacing: 18) {
                widget
                row("编辑小组件", icon: "pencil")
            }
        case 2:
            VStack(spacing: 18) {
                Text(appName).fontWeight(.semibold)
                row("显示账户", icon: "chevron.right")
            }
        default:
            VStack(alignment: .leading, spacing: 14) {
                Text("显示账户").fontWeight(.semibold)
                row("账号 A", icon: "circle")
                row("账号 B", icon: "checkmark.circle.fill")
            }
        }
    }

    private var icons: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
            ForEach(0..<8) { _ in
                RoundedRectangle(cornerRadius: 8).fill(DashboardStyle.track).frame(height: 28)
            }
        }
    }
    private var widget: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Codex").fontWeight(.semibold)
            Capsule().fill(DashboardStyle.track).frame(height: 8)
            Capsule().fill(DashboardStyle.track).frame(height: 8)
        }
        .padding(14).background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 16))
    }
    private func touch(moving: Bool) -> some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 30))
            .padding(12)
            .background(DashboardStyle.track.opacity(0.5), in: Circle())
            .symbolEffect(.pulse, options: .repeating, isActive: moving)
    }
    private func row(_ label: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Text(label).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: icon)
        }.padding(10).background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 10))
    }
    private func size(_ label: String, medium: Bool) -> some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 12).strokeBorder(DashboardStyle.secondary, lineWidth: 2)
                .frame(width: medium ? 116 : 58, height: 58)
            Text(label).font(.caption)
        }
    }
    private func action(_ label: String) -> some View {
        Text(label).fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)
            .padding(10).frame(maxWidth: .infinity)
            .foregroundStyle(DashboardStyle.accentText)
            .background(DashboardStyle.accent, in: RoundedRectangle(cornerRadius: 12))
    }
}
