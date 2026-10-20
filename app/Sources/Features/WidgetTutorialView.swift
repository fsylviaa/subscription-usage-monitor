import SwiftUI

/// Shared tutorial. Navigation never performs a system widget operation.
struct WidgetTutorialView: View {
    var close: () -> Void
    @State private var step = 0
    @State private var pageHeights: [Int: CGFloat] = [:]
    @State private var headerHeight: CGFloat = 52
    @State private var footerHeight: CGFloat = 100

    private var pageHeight: CGFloat { pageHeights[step] ?? 440 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    AppIconView(.close, size: 18).frame(width: 44, height: 44)
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
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headerHeight = $0 }

            TabView(selection: $step) {
                ForEach(0..<2) { page in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            WidgetOperationIllustration(page: page, active: step == page)
                                .frame(maxWidth: .infinity)
                                .padding(10)
                                .background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 26))

                            Text(page == 0
                                 ? "长按主屏幕，然后添加 TokenLeft。"
                                 : "长按小组件，选择要显示的账号")
                                .font(.title2.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("tutorial.instructions.\(page)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { pageHeights[page] = $0 }
                    }
                    .clipped()
                    .tag(page)
                    .accessibilityHidden(step != page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier("tutorial.pages")
            .frame(maxHeight: pageHeight)

            VStack(spacing: 10) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { footerHeight = $0 }
        }
        // iOS caps this content-sized detent at the available height. The pager
        // yields space to the controls; long text/static frames scroll inside it.
        .presentationDetents([.height(headerHeight + pageHeight + footerHeight)])
        .foregroundStyle(DashboardStyle.text)
        .background(DashboardStyle.background)
        .buttonStyle(.plain)
    }

}

/// Navigation and system actions remain independent from the demonstration.
private struct WidgetOperationIllustration: View {
    let page: Int
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var frame = 0
    @State private var cycle = 0
    @ScaledMetric(relativeTo: .body) private var preferredWidth = 250

    private var count: Int { page == 0 ? 8 : 4 }
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
        .accessibilityValue(reduceMotion ? "静态关键画面" : "画面 \(frame + 1)，共 \(count) 个" + (page == 0 ? "，循环 \(cycle + 1)" : ""))
        .accessibilityIdentifier("tutorial.demo.\(page)")
        .task(id: "\(active)-\(reduceMotion)-\(scenePhase)") {
            guard active, !reduceMotion, scenePhase == .active else { return }
            frame = 0
            cycle = 0
            repeat {
                for next in 1..<count {
                    do { try await Task.sleep(for: .seconds(page == 0 ? 1.4 : 2)) } catch { return }
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: page == 0 ? 0.18 : 0.25)) { frame = next }
                }
                // Only the first demonstration loops; inactive/background tasks cancel.
                guard page == 0 else { return }
                do { try await Task.sleep(for: .seconds(1.4)) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.18)) { frame = 0; cycle += 1 }
            } while !Task.isCancelled
        }
    }

    @ViewBuilder
    private func phone(_ index: Int, moving: Bool) -> some View {
        if page == 0 {
            WidgetAddingSystemPage(index: index, appName: appName, moving: moving)
        } else {
            GeometryReader { geometry in
                VStack(spacing: 16) {
                    Capsule().fill(DashboardStyle.text).frame(width: 48, height: 5)
                    choosing(index, moving: moving)
                        .id(index)
                        .transition(.opacity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Capsule().fill(DashboardStyle.secondary).frame(width: 62, height: 4)
                }
                .font(.subheadline)
                .padding(18)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(DashboardStyle.background, in: RoundedRectangle(cornerRadius: 30))
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(DashboardStyle.track, lineWidth: 2))
            }
            .aspectRatio(414.0 / 520, contentMode: .fit)
            .frame(maxWidth: preferredWidth)
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
}

/// Compact adaptation of the already verified system flow.
/// Only two rows of anonymous placeholders remain on the Home Screen.
/// All frames share the same bounds so looping never shifts the instruction title.
private struct WidgetAddingSystemPage: View {
    let index: Int
    let appName: String
    let moving: Bool
    @ScaledMetric(relativeTo: .body) private var preferredWidth = 250
    private let width: CGFloat = 414
    private let height: CGFloat = 520
    private var sheetVisible: Bool { (3...6).contains(index) }
    private var editing: Bool { index != 0 }

    var body: some View {
        // Compact frames scale together without changing height between animation stages.
        GeometryReader { geometry in
            let scale = geometry.size.width / width
            scene
                .frame(width: width, height: height)
                .environment(\.dynamicTypeSize, .medium)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: width * scale, height: height * scale, alignment: .topLeading)
                .frame(maxWidth: .infinity)
        }
        .aspectRatio(width / height, contentMode: .fit)
        .frame(maxWidth: preferredWidth)
    }

    private var scene: some View {
        ZStack(alignment: .topLeading) {
            home
            if index == 2 { editMenu.transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity)) }
            if sheetVisible {
                systemSheet.transition(.move(edge: .bottom))
            }
            pointer
        }
        .foregroundStyle(Color.primary)
    }

    private var systemSheet: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30)
                .fill(Color(.secondarySystemBackground))
                .frame(width: width, height: height - 62).offset(y: 62)
            Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 36, height: 5).offset(x: 189, y: 74)
            if index < 5 { gallery.id(index).transition(.opacity) }
            else { preview.transition(.opacity) }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private var home: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [DashboardStyle.track, DashboardStyle.elevated, DashboardStyle.background], startPoint: .topLeading, endPoint: .bottomTrailing)
            if editing {
                systemPill("编辑").offset(x: 28, y: 16)
                systemPill("完成").offset(x: 326, y: 16)
            }
            ForEach(0..<8, id: \.self) { item in
                let row = item / 4, column = item % 4
                appTile(editing: editing).offset(x: CGFloat(33 + column * 94), y: CGFloat(80 + row * 104) + (index == 7 ? 186 : 0))
            }
            if index == 7 {
                quotaPreview(medium: true).frame(width: 355, height: 166).offset(x: 29, y: 70)
                Text(appName).font(.system(size: 12)).frame(width: 355).offset(x: 29, y: 244)
            }
        }
    }

    private func appTile(editing: Bool) -> some View {
        RoundedRectangle(cornerRadius: 15).fill(DashboardStyle.secondary.opacity(0.22))
            .frame(width: 64, height: 64)
            .overlay(alignment: .topLeading) {
                if editing {
                    Image(systemName: "minus").font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24).background(.regularMaterial, in: Circle()).offset(x: -5, y: -5)
                }
            }
    }

    private func systemPill(_ text: String) -> some View {
        Text(text).font(.system(size: 16, weight: .semibold)).frame(width: 60, height: 26)
            .background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4)))
    }

    private var editMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow("添加小组件", symbol: "widget.small.badge.plus")
            menuRow("自定义", symbol: "apps.iphone")
            menuRow("编辑墙纸", symbol: "photo")
            menuRow("编辑页面", symbol: "rectangle.on.rectangle")
        }
        .padding(.vertical, 8).frame(width: 250, height: 188)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .offset(x: 25, y: 49)
    }
    private func menuRow(_ text: String, symbol: String) -> some View {
        HStack(spacing: 14) { Image(systemName: symbol).frame(width: 22); Text(text); Spacer() }
            .font(.system(size: 17)).padding(.horizontal, 29).frame(height: 42)
    }

    private var gallery: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(index == 4 ? appName : "搜索小组件").foregroundStyle(index == 4 ? Color.primary : .secondary)
                if index == 4 { Spacer(); Image(systemName: "xmark.circle.fill") }
            }
            .font(.system(size: 20)).padding(.horizontal, 22)
            .frame(width: index == 4 ? 301 : 356, height: 44)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule()).offset(x: 29, y: 98)
            if index == 4 {
                Image(systemName: "xmark").font(.system(size: 24)).frame(width: 44, height: 44)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle()).offset(x: 341, y: 98)
                HStack(spacing: 16) { appIcon.frame(width: 48, height: 48); Text(appName).font(.system(size: 18, weight: .semibold)) }
                    .offset(x: 29, y: 176)
                keyboard.offset(y: 300)
            } else {
                // Keep the real gallery's two-column cards without copying personal suggestions.
                VStack(alignment: .leading, spacing: 12) {
                    Text("最近").font(.system(size: 17, weight: .semibold))
                    HStack(spacing: 22) {
                        ForEach(0..<4) { _ in
                            RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill)).frame(width: 62, height: 62)
                        }
                    }
                }.padding(16).frame(width: 356, height: 122, alignment: .topLeading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 30))
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
                    .offset(x: 29, y: 174)
                ForEach(0..<2) { card in
                    VStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 30).fill(Color(.secondarySystemGroupedBackground))
                            .frame(width: 166, height: 146)
                            .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
                    }.offset(x: card % 2 == 0 ? 29 : 219, y: CGFloat(320 + card / 2 * 170))
                }
            }
        }
    }

    private var appIcon: some View {
        RoundedRectangle(cornerRadius: 7).fill(DashboardStyle.secondary.opacity(0.22))
    }

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 8) { appIcon.frame(width: 30, height: 30); Text(appName).font(.system(size: 16, weight: .semibold)) }
                .offset(x: 21, y: 84)
            Image(systemName: "xmark").font(.system(size: 23)).offset(x: 373, y: 84)
            Text("订阅额度").font(.system(size: 27, weight: .bold)).frame(width: width).offset(y: 142)
            Text("长按编辑小组件，为每个组件选择显示账户。")
                .font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 382).offset(x: 16, y: 180)
            ZStack(alignment: .topLeading) {
                quotaPreview(medium: false).frame(width: 166, height: 166)
                    .offset(x: index == 6 ? -150 : 124)
                quotaPreview(medium: true).frame(width: 355, height: 166)
                    .offset(x: index == 6 ? 29 : 400)
            }.frame(width: width, height: 166).offset(y: 240)
            if index == 5 {
                Image(systemName: "arrow.left").font(.system(size: 24)).foregroundStyle(.secondary).offset(x: 196, y: 416)
            }
            HStack(spacing: 10) { ForEach(0..<2) { dot in Circle().fill(dot == (index == 6 ? 1 : 0) ? Color.primary : Color.secondary).frame(width: 7, height: 7) } }
                .offset(x: 194, y: 448)
            Label("添加小组件", systemImage: "plus.circle.fill").font(.system(size: 20))
                .foregroundStyle(Color(.systemBackground)).frame(width: 366, height: 42)
                .background(Color.primary, in: Capsule()).offset(x: 24, y: 465)
        }
    }

    private func quotaPreview(medium: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image("DesignCodex").resizable().renderingMode(.template).frame(width: 22, height: 22)
                    .padding(4).background(DashboardStyle.elevated, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex").font(.system(size: 14, weight: .semibold))
                    Text("账号 A").font(.system(size: 11)).foregroundStyle(DashboardStyle.secondary)
                }
            }
            ForEach(["每周", "5 小时"], id: \.self) { title in
                VStack(spacing: 4) {
                    HStack { Text(title).font(.system(size: 12)); Spacer(); Text("剩余 90%").font(.system(size: 16, weight: .semibold)) }
                    Capsule().fill(DashboardStyle.track).frame(height: 6)
                        .overlay(alignment: .leading) { Capsule().fill(DashboardStyle.text).frame(width: medium ? 32 : 14, height: 6) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14).foregroundStyle(DashboardStyle.text)
        .background(DashboardStyle.background, in: RoundedRectangle(cornerRadius: 30))
    }

    private var keyboard: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 16)
            keyRow(Array("qwertyuiop").map(String.init))
            keyRow(Array("asdfghjkl").map(String.init)).padding(.horizontal, 14)
            keyRow(["⇧"] + Array("zxcvbnm").map(String.init) + ["⌫"])
            HStack(spacing: 6) {
                key("123").frame(width: 44); key("☺︎").frame(width: 44)
                key("").frame(maxWidth: .infinity)
                Image(systemName: "magnifyingglass").font(.system(size: 22)).frame(width: 95, height: 32).foregroundStyle(.white).background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack { Image(systemName: "globe"); Spacer(); Image(systemName: "mic") }.font(.system(size: 24)).padding(.horizontal, 27).padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).frame(width: width, height: 220)
        .background(Color(.systemGray4), in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
    }
    private func keyRow(_ letters: [String]) -> some View {
        HStack(spacing: 6) { ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in key(letter).frame(maxWidth: .infinity) } }
    }
    private func key(_ letter: String) -> some View {
        Text(letter).font(.system(size: 20)).frame(height: 32).frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var pointer: some View {
        let points: [CGPoint] = [.init(x: 330, y: 280), .init(x: 65, y: 35), .init(x: 150, y: 76), .init(x: 207, y: 115), .init(x: 160, y: 205), .init(x: 280, y: 295), .init(x: 207, y: 475), .init(x: 354, y: 35)]
        return Image(systemName: "hand.point.up.left.fill").font(.system(size: 30))
            .foregroundStyle(DashboardStyle.text).padding(10).background(DashboardStyle.elevated.opacity(0.9), in: Circle())
            .offset(x: points[index].x - 16, y: points[index].y)
    }
}
