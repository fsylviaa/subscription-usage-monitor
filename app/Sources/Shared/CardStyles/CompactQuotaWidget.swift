import SwiftUI

/// Small and medium widget layouts of the approved comparison page
/// (smallWidget / mediumWidget, 霓虹派对 widgets()). Static, no e-mail, no
/// time and no visible “剩余”. Background and border are drawn by the host.
struct CompactWidgetBody: View {
    let style: QuotaCardStyle
    let input: QuotaStyledInput
    let medium: Bool
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    private var theme: CompactQuotaTheme { style.compactTheme(dark: dark, widget: true) }
    private func c(_ light: String, _ dark: String) -> Color { .quotaHex(self.dark ? dark : light) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, style == .rave ? 8 : (medium ? 10 : 9))
            if input.windows.isEmpty {
                Text(input.message ?? "尚未获取额度").font(.system(size: 13)).foregroundStyle(theme.muted)
                    .lineLimit(2)
            } else if medium {
                mediumBody
            } else {
                smallBody
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(theme.ink)
        .padding(.horizontal, 14).padding(.vertical, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { decoration }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native.\(style.rawValue).\(medium ? "mediumWidget" : "smallWidget")")
    }

    // MARK: Header and decoration

    private var header: some View {
        HStack(spacing: 0) {
            if style == .watermark {
                PlatformMarkShape(platform: input.platform).fill(theme.ink, style: PlatformMarkShape.fillStyle).frame(width: medium ? 16 : 15, height: medium ? 16 : 15)
                    .padding(.trailing, 5).accessibilityHidden(true)
            }
            if style == .neumorph { NeumorphMarkTile(platform: input.platform, size: medium ? 20 : 18).padding(.trailing, 7) }
            if style == .rave {
                Text(input.platform.displayName).font(.system(size: medium ? 14 : 13, weight: .black))
                    .shadow(color: RavePalette.shadow, radius: 0, x: 2, y: 2)
            } else {
                Text(input.platform.displayName).font(.system(size: medium ? 14 : 13, weight: .bold))
            }
            if style == .rave { RaveSpark().frame(width: 12, height: 12).padding(.leading, 6) }
        }
        .lineLimit(1).minimumScaleFactor(0.7)
    }

    @ViewBuilder private var decoration: some View {
        ZStack(alignment: .topTrailing) {
            if style == .rave {
                if medium {
                    ghost("CLUB", size: 52).offset(x: -6, y: -4)
                } else {
                    ForEach(Array(input.windows.prefix(2).enumerated()), id: \.offset) { index, w in
                        ghost(w.amount.nativeText.replacingOccurrences(of: "%", with: ""), size: 58).offset(x: 6, y: index == 0 ? 30 : 92)
                    }
                }
                CompactQuotaWatermark(style: style, size: medium ? 150 : 120, right: medium ? -30 : -26, bottom: medium ? -34 : -24)
            } else {
                CompactQuotaWatermark(style: style, size: medium ? 150 : 110, right: medium ? -30 : -24, bottom: medium ? -34 : -22)
            }
        }
    }

    private func ghostText(_ text: String, size: CGFloat) -> some View {
        Text(text).font(.system(size: size, weight: .black)).tracking(-2).foregroundStyle(RavePalette.echo)
            .lineLimit(1).fixedSize().accessibilityHidden(true)
    }

    private func ghost(_ text: String, size: CGFloat) -> some View {
        ghostText(text, size: size).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    // MARK: Small

    @ViewBuilder private var smallBody: some View {
        let ws = input.windows
        switch style {
        case .island:
            VStack(spacing: 0) {
                ForEach(Array(ws.enumerated()), id: \.element.id) { i, w in
                    VStack(spacing: 5) {
                        labelRow(w, label: .quotaHex("a9bca8"), number: .quotaHex("f4fff1"), size: 22)
                        bar(w, height: 6)
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) { if i < ws.count - 1 { Rectangle().fill(Color.quotaHex("2a2f2b")).frame(height: 1) } }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(LinearGradient(colors: [.quotaHex("080a09"), .quotaHex("101311")], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.quotaHex("3b423d"), lineWidth: 1) }
        case .dials:
            HStack(alignment: .top, spacing: 6) {
                ForEach(ws) { w in
                    VStack(spacing: 0) {
                        Text(w.title).font(.system(size: 11, weight: .semibold))
                        if !w.isBalance { gauge(w).frame(width: 68, height: 62).padding(.top, 3) }
                        number(w, size: 22, weight: .bold).padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity)
                    .modifier(WindowLabel(window: w))
                }
            }
        case .panels:
            VStack(spacing: 7) {
                ForEach(ws) { w in
                    VStack(spacing: 5) {
                        labelRow(w, number: w.weekly ? .quotaHex("26180f") : nil, size: 22)
                        bar(w, height: 12, secondary: !w.weekly)
                    }
                    .foregroundStyle(w.weekly ? Color.quotaHex("26180f") : theme.ink)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(panelFill(w.weekly), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay { if !w.weekly { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(c("d5cdc3", "4b4e52"), lineWidth: 1) } }
                }
            }
        case .rave:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ws) { w in
                    VStack(spacing: 6) {
                        HStack(alignment: .lastTextBaseline) {
                            Text(w.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(RavePalette.green)
                            Spacer(minLength: 2)
                            raveNumber(w, size: 26)
                        }
                        bar(w, height: 9)
                    }
                    .modifier(WindowLabel(window: w))
                }
            }
        default:
            VStack(spacing: 11) {
                ForEach(ws) { w in
                    VStack(spacing: 5) {
                        labelRow(w, size: style == .watermark ? 28 : 24)
                        bar(w, height: miniHeight)
                    }
                }
            }
        }
    }

    // MARK: Medium

    @ViewBuilder private var mediumBody: some View {
        let ws = input.windows
        HStack(alignment: .top, spacing: 18) {
            ForEach(ws) { w in mediumColumn(w).frame(maxWidth: .infinity, alignment: .leading).modifier(WindowLabel(window: w)) }
        }
    }

    @ViewBuilder private func mediumColumn(_ w: QuotaStyledInput.Window) -> some View {
        switch style {
        case .island:
            VStack(alignment: .leading, spacing: 0) {
                mediumLabel(w, color: .quotaHex("a9bca8"))
                number(w, size: 32, weight: .bold, color: .quotaHex("f4fff1")).padding(.top, 5).padding(.bottom, 9)
                bar(w, height: 7)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(LinearGradient(colors: [.quotaHex("080a09"), .quotaHex("101311")], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.quotaHex("3b423d"), lineWidth: 1) }
        case .dials:
            VStack(alignment: .leading, spacing: 4) {
                mediumLabel(w)
                HStack(spacing: 8) {
                    if !w.isBalance { gauge(w).frame(width: 68, height: 62) }
                    number(w, size: 30, weight: .bold)
                }
            }
        case .panels:
            VStack(alignment: .leading, spacing: 0) {
                mediumLabel(w)
                number(w, size: 34, weight: .bold, color: w.weekly ? .quotaHex("26180f") : nil).padding(.top, 5).padding(.bottom, 9)
                bar(w, height: 14, secondary: !w.weekly)
            }
            .foregroundStyle(w.weekly ? Color.quotaHex("26180f") : theme.ink)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(panelFill(w.weekly), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(w.weekly ? .clear : c("d5cdc3", "4b4e52"), lineWidth: 1) }
        case .blocks, .glass, .ticket, .neumorph:
            VStack(alignment: .leading, spacing: 0) {
                mediumLabel(w)
                number(w, size: 34, weight: .bold).padding(.top, 5).padding(.bottom, 9)
                bar(w, height: miniHeight)
            }
            .padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 11)
            .background { mediumPanel }
        case .rave:
            VStack(alignment: .leading, spacing: 0) {
                mediumLabel(w, color: RavePalette.green)
                raveNumber(w, size: 42)
                    .background(alignment: .topLeading) { ghostText(w.amount.nativeText, size: 70).offset(x: -4, y: -10) }
                    .padding(.top, 4).padding(.bottom, 12)
                bar(w, height: 12)
            }
            .padding(.top, 8)
        default:
            VStack(alignment: .leading, spacing: 0) {
                mediumLabel(w)
                number(w, size: style == .watermark ? 44 : 40, weight: .bold).padding(.top, 5).padding(.bottom, 9)
                bar(w, height: miniHeight)
            }
        }
    }

    @ViewBuilder private var mediumPanel: some View {
        let shape = RoundedRectangle(cornerRadius: style == .ticket ? 7 : 13, style: .continuous)
        switch style {
        case .blocks:
            shape.fill(c("faf7ff", "1b1a21")).overlay { shape.strokeBorder(c("ddd2ee", "423a51"), lineWidth: 1) }
        case .glass:
            shape.fill(dark ? Color(.sRGB, red: 30 / 255, green: 50 / 255, blue: 85 / 255, opacity: 0.55) : .white.opacity(0.55))
                .overlay { shape.strokeBorder(dark ? Color(.sRGB, red: 137 / 255, green: 204 / 255, blue: 239 / 255, opacity: 0.35) : .white, lineWidth: 1) }
        case .neumorph:
            // D-84: a raised cream panel inside the widget (static; shadows stay within the widget).
            shape.fill(NeumorphPalette.surface(dark: dark))
                .overlay { shape.strokeBorder(NeumorphPalette.rim(dark: dark), lineWidth: 1) }
                .neumorphRaised(dark: dark, small: true)
        default:
            shape.fill(c("fffef9", "202124")).overlay { shape.strokeBorder(c("222222", "a3a5a8"), lineWidth: 2) }
        }
    }

    // MARK: Pieces

    private var miniHeight: CGFloat {
        switch style {
        case .capsule, .blocks: 14
        case .liquid: 18
        case .watermark: 7
        case .neumorph: 10
        default: 16
        }
    }

    private func panelFill(_ main: Bool) -> AnyShapeStyle {
        main ? AnyShapeStyle(LinearGradient(colors: [.quotaHex("eb782f"), .quotaHex("f2a265")], startPoint: .topLeading, endPoint: .bottomTrailing))
             : AnyShapeStyle(c("eeeae4", "242629"))
    }

    private func labelRow(_ w: QuotaStyledInput.Window, label: Color? = nil, number nc: Color? = nil, size: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(w.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(label ?? theme.ink)
            Spacer(minLength: 2)
            number(w, size: size, weight: .bold, color: nc)
        }
        .modifier(WindowLabel(window: w))
    }

    private func mediumLabel(_ w: QuotaStyledInput.Window, color: Color? = nil) -> some View {
        Text(w.longTitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(color ?? theme.ink).lineLimit(1)
    }

    private func number(_ w: QuotaStyledInput.Window, size: CGFloat, weight: Font.Weight, color: Color? = nil) -> some View {
        Text(w.amount.nativeText).font(.system(size: size, weight: weight)).tracking(size > 30 ? -1 : -0.5)
            .monospacedDigit().foregroundStyle(color ?? theme.ink).lineLimit(1).minimumScaleFactor(0.5)
    }

    private func raveNumber(_ w: QuotaStyledInput.Window, size: CGFloat) -> some View {
        Text(w.amount.nativeText).font(.system(size: size, weight: .black)).tracking(-1)
            .foregroundStyle(RavePalette.magenta).shadow(color: RavePalette.shadow, radius: 0, x: size > 30 ? 3 : 2, y: size > 30 ? 3 : 2)
            .lineLimit(1).minimumScaleFactor(0.5)
    }

    /// Unknown / unlimited reserve the row but never draw a ratio.
    @ViewBuilder private func bar(_ w: QuotaStyledInput.Window, height: CGFloat, secondary: Bool = false) -> some View {
        if let f = w.amount.remainingFraction {
            CompactQuotaBar(style: style, fraction: f, mini: true, secondary: secondary, phase: nil).frame(height: height)
        } else if !w.isBalance {
            Color.clear.frame(height: height)
        }
    }

    /// A balance has no ratio, so no gauge and no reserved gauge space.
    @ViewBuilder private func gauge(_ w: QuotaStyledInput.Window) -> some View {
        if let f = w.amount.remainingFraction { CompactMiniGauge(fraction: f) } else if !w.isBalance { Color.clear }
    }
}

/// One spoken element per window: “每周额度，剩余 90%”.
private struct WindowLabel: ViewModifier {
    let window: QuotaStyledInput.Window
    func body(content: Content) -> some View {
        content.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(window.longTitle)，" + (window.amount.remainingFraction == nil ? window.amount.nativeText : "剩余 " + window.amount.nativeText))
    }
}

/// Widget/preview chrome: the style's background plus its frame line.
struct CompactWidgetChrome<S: InsettableShape>: ViewModifier {
    let style: QuotaCardStyle
    let shape: S
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let theme = style.compactTheme(dark: scheme == .dark, widget: true)
        content.overlay { shape.strokeBorder(theme.widgetBorder, lineWidth: theme.widgetBorderWidth).allowsHitTesting(false) }
    }
}
