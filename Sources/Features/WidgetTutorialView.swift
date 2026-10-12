import SwiftUI

/// Static system instructions. Advancing or closing never installs a widget.
struct WidgetTutorialView: View {
    var close: () -> Void
    @State private var secondStep = false

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

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    illustration
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 26))
                        .accessibilityHidden(true)
                    Text(secondStep ? "搜索 App，选择尺寸并添加" : "长按主屏幕，进入添加入口")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("tutorial.stepTitle")
                    Text(secondStep
                         ? "搜索“订阅用量”，选择小号或中号，轻点“添加小组件”，再轻点“完成”。"
                         : "长按主屏幕空白处，轻点左上角“编辑”，再选择“添加小组件”。")
                        .font(.body)
                        .foregroundStyle(DashboardStyle.secondary)
                        .accessibilityIdentifier("tutorial.instructions")
                    if secondStep {
                        Text("默认显示账户列表中的第一个账户。")
                            .font(.subheadline).foregroundStyle(DashboardStyle.secondary)
                            .accessibilityIdentifier("tutorial.defaultAccount")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .clipped()

            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Capsule().fill(secondStep ? DashboardStyle.track : DashboardStyle.text)
                        .frame(width: secondStep ? 6 : 18, height: 6)
                    Capsule().fill(secondStep ? DashboardStyle.text : DashboardStyle.track)
                        .frame(width: secondStep ? 18 : 6, height: 6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(secondStep ? "第 2 步，共 2 步" : "第 1 步，共 2 步")
                .accessibilityIdentifier("tutorial.step")
                Button(secondStep ? "完成" : "继续") {
                    if secondStep { close() } else { secondStep = true }
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

    @ViewBuilder
    private var illustration: some View {
        if secondStep {
            VStack(spacing: 18) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("订阅用量")
                    Spacer()
                }
                .font(.subheadline).padding(12)
                .background(DashboardStyle.background, in: RoundedRectangle(cornerRadius: 12))
                HStack(alignment: .bottom, spacing: 16) {
                    sizeDiagram("小号", width: 66)
                    sizeDiagram("中号", width: 132)
                }
                Text("添加小组件").font(.subheadline.weight(.semibold))
                    .padding(12).frame(maxWidth: .infinity)
                    .foregroundStyle(DashboardStyle.accentText)
                    .background(DashboardStyle.accent, in: RoundedRectangle(cornerRadius: 14))
            }
        } else {
            VStack(spacing: 20) {
                HStack {
                    Text("编辑").font(.subheadline.weight(.semibold)).padding(10)
                        .background(DashboardStyle.elevated, in: Capsule())
                    Spacer()
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(0..<12) { _ in
                        RoundedRectangle(cornerRadius: 9).fill(DashboardStyle.track)
                            .frame(height: 30)
                    }
                }
                HStack {
                    Spacer()
                    Image(systemName: "hand.point.up.left.fill").font(.system(size: 32))
                }
            }
            .padding(16).frame(maxWidth: 224)
            .background(DashboardStyle.background, in: RoundedRectangle(cornerRadius: 28))
        }
    }

    private func sizeDiagram(_ title: String, width: CGFloat) -> some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 14).strokeBorder(DashboardStyle.secondary, lineWidth: 2)
                .frame(width: width, height: 66)
            Text(title).font(.caption)
        }
    }
}
