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
                            illustration(secondStep: page == 1)
                                .frame(maxWidth: .infinity)
                                .padding(24)
                                .background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 26))
                                .accessibilityHidden(true)
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

    @ViewBuilder
    private func illustration(secondStep: Bool) -> some View {
        if secondStep {
            VStack(spacing: 18) {
                sizeDiagram("", width: 132)
                Text("编辑小组件").font(.subheadline.weight(.semibold))
                HStack {
                    Text("显示账户")
                    Spacer()
                    Text("账号").foregroundStyle(DashboardStyle.secondary)
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline).padding(12)
                .background(DashboardStyle.background, in: RoundedRectangle(cornerRadius: 12))
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
