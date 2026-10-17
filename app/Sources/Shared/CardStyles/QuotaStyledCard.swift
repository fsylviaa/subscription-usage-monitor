import SwiftUI

/// The single renderer for every surface (D-76). Layouts follow the approved
/// comparison page: account card = `render()`, detail card = the same style for
/// one window. No visible “剩余”; VoiceOver still reads it. Display only.
struct QuotaStyledCard: View {
    let style: QuotaCardStyle
    let input: QuotaStyledInput
    var surface: QuotaCardSurface = .account
    var now: Date = .now
    var accessory: AnyView? = nil
    /// The platform title opens the account details (account surface only).
    var openDetails: (() -> Void)? = nil
    /// Alternates decorative back-layer words between neighbouring cards.
    var variant = 0
    /// Never drawn (D-72: no e-mail on the card); read by VoiceOver only, so
    /// several accounts on the same platform can still be told apart.
    var spokenIdentity: String? = nil
    /// The App's own latest attempt failed for an account that never had quota.
    var failed = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.nativeQuotaStatic) private var forcedStatic
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .headline) private var headerSize = 17
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 15
    @ScaledMetric(relativeTo: .footnote) private var resetSize = 13
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 36

    private var widget: Bool { surface == .smallWidget || surface == .mediumWidget }
    private var detail: Bool { surface == .detail }
    private var large: Bool { typeSize.isAccessibilitySize }
    private var dark: Bool { scheme == .dark }
    private var theme: CompactQuotaTheme { style.compactTheme(dark: dark) }
    private var motion: Bool {
        surface.motion(reduceMotion: reduceMotion || forcedStatic) == .measuredChanges && scenePhase == .active
    }
    private var idPrefix: String { detail ? "detail" : "quota" }
    private func c(_ light: String, _ dark: String) -> Color { .quotaHex(self.dark ? dark : light) }

    var body: some View {
        Group {
            if widget {
                CompactWidgetBody(style: style, input: input, medium: surface == .mediumWidget)
            } else {
                card
            }
        }
        .environment(\.quotaPlatform, input.platform)
    }

    // MARK: Card chrome

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !detail { header.padding(.bottom, style == .journal ? 8 : 12)
                .overlay(alignment: .bottom) {
                    if style == .journal {
                        Line().stroke(theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
                    }
                }
                .padding(.bottom, style == .journal ? 12 : 0)
            }
            if input.windows.isEmpty {
                let message = failed && input.message == "尚未获取额度" ? "刷新失败" : (input.message ?? "尚未获取额度")
                Text(message).font(.system(size: titleSize)).foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(detail ? "detail.styleStatus" : message == "尚未获取额度" ? "quota.notFetched"
                        : message == "无适用额度" ? "quota.notApplicable" : "quota.accountStatus")
            } else {
                windows
                // A failed refresh keeps every trusted value and its original time.
                if let message = input.message {
                    Text(message).font(.system(size: resetSize)).foregroundStyle(theme.muted).padding(.top, 10)
                }
            }
        }
        .foregroundStyle(theme.ink)
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, style == .rave ? 20 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topLeading) {
                CompactQuotaBackground(style: style)
                if style == .rave && !detail {
                    ghost(variant % 2 == 0 ? "NIGHT" : "PARTY", size: 64).offset(x: 44, y: -4)
                }
                CompactQuotaWatermark(style: style, size: 180, right: -34, bottom: -30)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: theme.radius, style: .continuous).strokeBorder(theme.border, lineWidth: theme.borderWidth) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native.\(style.rawValue).\(String(describing: surface))")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            if style == .watermark { PlatformMarkShape(platform: input.platform).fill(theme.ink, style: PlatformMarkShape.fillStyle).frame(width: 24, height: 24).accessibilityHidden(true) }
            Button { openDetails?() } label: {
                // Two children keep the platform title exposed as its own text.
                ZStack(alignment: .bottomLeading) {
                    headerTitle.multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("quota.plan")
                    if let spokenIdentity {
                        // Never drawn (D-72); VoiceOver can still tell accounts apart.
                        Text(spokenIdentity).font(.system(size: 1)).foregroundStyle(.clear)
                            .frame(width: 1, height: 1).clipped()
                            .privacySensitive()
                            .accessibilityIdentifier("quota.accountIdentity")
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(openDetails == nil)
            .accessibilityHint("查看账户详情")
            .accessibilityIdentifier("quota.details")
            if style == .rave { RaveSpark().frame(width: 16, height: 16).accessibilityHidden(true) }
            Spacer(minLength: 0)
            if let accessory { accessory.padding(.vertical, -8) }
        }
    }

    /// Platform name only; plan names are never shown (D-77).
    private var headerTitle: Text {
        if style == .rave {
            return Text(input.platform.displayName).font(.system(size: headerSize + 2, weight: .black))
        }
        return Text(input.platform.displayName).font(.system(size: headerSize, weight: .semibold))
    }

    // MARK: Per-style window layouts

    @ViewBuilder private var windows: some View {
        let ws = input.windows
        switch style {
        case .skala, .capsule, .ticks, .journal:
            VStack(alignment: .leading, spacing: 14) {
                ForEach(ws) { w in
                    VStack(alignment: .leading, spacing: 8) {
                        topLine(w)
                        bar(w, height: style == .capsule ? 26 : style == .ticks ? 30 : 32)
                    }
                }
            }
        case .island:
            VStack(spacing: 0) {
                ForEach(Array(ws.enumerated()), id: \.element.id) { index, w in
                    VStack(alignment: .leading, spacing: 9) {
                        topLine(w, title: .quotaHex("f4fff1"), reset: .quotaHex("a9bca8"), number: .quotaHex("f4fff1"))
                        bar(w, height: 10)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        if index < ws.count - 1 { Rectangle().fill(Color.quotaHex("2a2f2b")).frame(height: 1) }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 2)
            .background(LinearGradient(colors: [.quotaHex("080a09"), .quotaHex("101311")], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.quotaHex("3b423d"), lineWidth: 1) }
        case .blocks, .liquid, .ticket, .glass:
            VStack(spacing: style == .liquid ? 14 : 10) {
                ForEach(ws) { w in
                    VStack(alignment: .leading, spacing: 0) {
                        infoLine(w).padding(.bottom, 8)
                        if style == .ticket {
                            Line().stroke(c("8c929b", "6d7076"), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .frame(height: 1).padding(.horizontal, -2).padding(.bottom, 10)
                        }
                        numberRow(w, height: style == .liquid ? 44 : style == .ticket ? 34 : style == .glass ? 32 : 36)
                    }
                    .modifier(InsetPanel(style: style, dark: dark))
                }
            }
        case .dials:
            pairGrid(ws) { w in
                [AnyView(title(w)), AnyView(reset(w, twoLines: true).padding(.top, 2)), AnyView(dial(w).padding(.top, 2))]
            }
        case .watermark:
            pairGrid(ws, spacing: 18) { w in
                [AnyView(title(w)),
                 AnyView(number(w, size: numberSize * 46 / 36).padding(.top, 4).padding(.bottom, 8)),
                 AnyView(bar(w, height: 9)),
                 AnyView(reset(w, twoLines: true).padding(.top, 6))]
            }
        case .panels:
            VStack(spacing: 10) { ForEach(ws) { w in w.weekly ? AnyView(orangePanel(w)) : AnyView(greyPanel(w)) } }
        case .rave:
            VStack(alignment: .leading, spacing: 16) {
                ForEach(ws) { w in
                    VStack(alignment: .leading, spacing: 0) {
                        topLine(w, title: RavePalette.green, reset: theme.muted, number: RavePalette.magenta, rave: true)
                            .padding(.bottom, 8)
                        bar(w, height: 16).padding(.top, 4)
                    }
                    .background(alignment: .topTrailing) { ghost(w.amount.nativeText, size: 92).offset(x: 8, y: -10) }
                }
            }
        }
    }

    // MARK: Building blocks

    private func title(_ w: QuotaStyledInput.Window, color: Color? = nil) -> some View {
        Text(w.title + "额度").font(.system(size: titleSize, weight: .semibold)).foregroundStyle(color ?? theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func reset(_ w: QuotaStyledInput.Window, twoLines: Bool = false, color: Color? = nil) -> some View {
        let text = NativeQuotaReset.text(w.resetsAt, now: now)
        return Text(twoLines ? text.replacingOccurrences(of: " · ", with: "\n") : text)
            .font(.system(size: resetSize)).foregroundStyle(color ?? theme.muted)
            .lineLimit(large || twoLines ? nil : 1).minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(w.resetsAt.map { $0 > now ? "预计重置于 " + $0.formatted(.dateTime.month().day().hour().minute()) : text } ?? text)
            .accessibilityValue(text)
            .accessibilityIdentifier("\(idPrefix).\(w.id).reset")
    }

    private func number(_ w: QuotaStyledInput.Window, size: CGFloat? = nil, color: Color? = nil, rave: Bool = false,
                        weight: Font.Weight = .semibold) -> some View {
        Text(w.amount.nativeText)
            .font(.system(size: size ?? numberSize, weight: rave ? .black : weight))
            .tracking(rave ? -1 : -0.5)
            .monospacedDigit()
            .foregroundStyle(color ?? theme.ink)
            .shadow(color: rave ? RavePalette.shadow : .clear, radius: 0, x: rave ? 3 : 0, y: rave ? 3 : 0)
            .lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityLabel(w.amount.remainingFraction == nil ? w.amount.nativeText : "剩余 " + w.amount.nativeText)
            .accessibilityIdentifier("\(idPrefix).\(w.id).remaining")
    }

    /// Name and time on the left, the large number on the right (bottom aligned).
    @ViewBuilder private func topLine(_ w: QuotaStyledInput.Window, title tc: Color? = nil, reset rc: Color? = nil,
                                      number nc: Color? = nil, numberScale: CGFloat = 1, rave: Bool = false) -> some View {
        let n = number(w, size: numberSize * numberScale * (rave ? 42.0 / 36 : 1), color: nc, rave: rave)
        if large {
            VStack(alignment: .leading, spacing: 4) { title(w, color: tc); reset(w, color: rc); n }
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) { title(w, color: tc); reset(w, color: rc) }
                    .layoutPriority(1)
                Spacer(minLength: 0)
                n.fixedSize()
            }
        }
    }

    @ViewBuilder private func infoLine(_ w: QuotaStyledInput.Window) -> some View {
        if large {
            VStack(alignment: .leading, spacing: 2) { title(w); reset(w) }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) { title(w); Spacer(minLength: 0); reset(w) }
        }
    }

    @ViewBuilder private func numberRow(_ w: QuotaStyledInput.Window, height: CGFloat) -> some View {
        if large {
            VStack(alignment: .leading, spacing: 8) { number(w); bar(w, height: height) }
        } else {
            HStack(spacing: 14) {
                number(w).frame(minWidth: 86, alignment: .leading).fixedSize()
                bar(w, height: height)
            }
        }
    }

    /// Unknown / unlimited windows reserve the space but never draw a ratio.
    @ViewBuilder private func bar(_ w: QuotaStyledInput.Window, height: CGFloat, secondary: Bool = false) -> some View {
        if let f = w.amount.remainingFraction {
            AnimatedCompactBar(style: style, fraction: f, mini: false, secondary: secondary, motion: motion)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(w.title)额度条")
                .accessibilityValue("已用 \(100 - (w.amount.wholeRemaining ?? 0))%，剩余 \(w.amount.nativeText)")
                .accessibilityIdentifier("\(idPrefix).\(w.id).bar")
        } else {
            Color.clear.frame(height: height).accessibilityHidden(true)
        }
    }

    /// Left/right columns share each row height (D-74 alignment); a single
    /// window or the largest text sizes stack instead.
    @ViewBuilder private func pairGrid(_ ws: [QuotaStyledInput.Window], spacing: CGFloat = 16,
                                       rows: @escaping (QuotaStyledInput.Window) -> [AnyView]) -> some View {
        if ws.count == 2 && !large {
            let a = rows(ws[0]), b = rows(ws[1])
            Grid(alignment: .topLeading, horizontalSpacing: spacing, verticalSpacing: 0) {
                ForEach(0..<a.count, id: \.self) { i in
                    GridRow { a[i].frame(maxWidth: .infinity, alignment: .leading); b[i].frame(maxWidth: .infinity, alignment: .leading) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(ws) { w in VStack(alignment: .leading, spacing: 0) { ForEach(Array(rows(w).enumerated()), id: \.offset) { $0.element } } }
            }
        }
    }

    @ViewBuilder private func dial(_ w: QuotaStyledInput.Window) -> some View {
        if let f = w.amount.remainingFraction {
            DialHost(fraction: f, motion: motion)
                .aspectRatio(160.0 / 150, contentMode: .fit)
                .frame(maxWidth: large ? 280 : 160)
                .overlay {
                    GeometryReader { g in
                        number(w, size: numberSize * 27 / 36, weight: .bold)
                            .position(x: g.size.width / 2, y: g.size.height * 106 / 150)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .contain)
        } else {
            number(w, size: numberSize * 27 / 36).frame(maxWidth: .infinity).frame(minHeight: 60)
        }
    }

    private func orangePanel(_ w: QuotaStyledInput.Window) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            topLine(w, title: .quotaHex("26180f"), reset: .quotaHex("5a3a22"), number: .quotaHex("26180f"))
            bar(w, height: 26)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(LinearGradient(colors: [.quotaHex("eb782f"), .quotaHex("f2a265")], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func greyPanel(_ w: QuotaStyledInput.Window) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if large {
                VStack(alignment: .leading, spacing: 4) { title(w); reset(w); number(w, size: numberSize * 30 / 36) }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) { title(w); reset(w) }.layoutPriority(1)
                    Spacer(minLength: 0)
                    number(w, size: numberSize * 30 / 36).fixedSize()
                }
            }
            bar(w, height: 16, secondary: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(c("eeeae4", "242629"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(c("d5cdc3", "4b4e52"), lineWidth: 1) }
    }

    /// 霓虹派对 back layer: very large, dark, same hue family as the ground.
    private func ghost(_ text: String, size: CGFloat) -> some View {
        Text(text).font(.system(size: size, weight: .black)).tracking(-2)
            .foregroundStyle(RavePalette.echo).lineLimit(1).fixedSize()
            .accessibilityHidden(true).allowsHitTesting(false)
    }
}

// MARK: - Helpers

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)); return p
    }
}

/// Inner panels of 紫色模块／黑白票签／冰蓝玻璃 (横向液体 has none).
private struct InsetPanel: ViewModifier {
    let style: QuotaCardStyle
    let dark: Bool
    func body(content: Content) -> some View {
        switch style {
        case .blocks:
            content.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)
                .background(dark ? AnyShapeStyle(LinearGradient(colors: [.quotaHex("17161b"), .quotaHex("242029")], startPoint: .topLeading, endPoint: .bottomTrailing))
                                 : AnyShapeStyle(Color.quotaHex("faf7ff")), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.quotaHex(dark ? "423a51" : "ddd2ee"), lineWidth: 1) }
        case .ticket:
            content.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
                .background(Color.quotaHex(dark ? "202124" : "fffef9"), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.quotaHex(dark ? "a3a5a8" : "222222"), lineWidth: 2) }
        case .glass:
            content.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)
                .background(dark ? Color(.sRGB, red: 30 / 255, green: 50 / 255, blue: 85 / 255, opacity: 0.55) : .white.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(dark ? Color(.sRGB, red: 137 / 255, green: 204 / 255, blue: 239 / 255, opacity: 0.35) : .white.opacity(0.95), lineWidth: 1) }
                .shadow(color: dark ? .black.opacity(0.25) : Color.quotaHex("4678aa").opacity(0.12), radius: 7, y: 4)
        default:
            content
        }
    }
}

/// App-only motion: value changes ease in, and styles with living material
/// (bubbles, laser sweep and tip) run a timeline. Widgets and reduced motion
/// receive a still frame.
struct AnimatedCompactBar: View {
    let style: QuotaCardStyle
    let fraction: Double
    var mini = false
    var secondary = false
    let motion: Bool

    private var living: Bool { motion && fraction > 0 && [.capsule, .glass, .rave].contains(style) }

    var body: some View {
        Group {
            if living {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { t in
                    bar(phase: t.date.timeIntervalSinceReferenceDate)
                }
            } else { bar(phase: nil) }
        }
    }

    private func bar(phase: Double?) -> some View {
        CompactQuotaBar(style: style, fraction: fraction, mini: mini, secondary: secondary, phase: phase)
            .animation(motion ? .easeOut(duration: 0.5) : nil, value: fraction)
            .transaction { t in
                // Account rows freeze their own layout; only this local graphic animates.
                t.disablesAnimations = !motion
                if !motion { t.animation = nil }
            }
    }
}

/// The needle swings in from E when the card appears (App only).
private struct DialHost: View {
    let fraction: Double
    let motion: Bool
    @State private var shown: Double?

    var body: some View {
        CompactDial(fraction: shown ?? (motion ? 0 : fraction))
            // Implicit animation sits inside the transaction that re-enables it,
            // because the account row clears animations for its own layout.
            .animation(motion ? .easeOut(duration: 0.9).delay(0.15) : nil, value: shown)
            .transaction { t in
                t.disablesAnimations = !motion
                if !motion { t.animation = nil }
            }
            .onAppear {
                guard motion else { shown = fraction; return }
                shown = 0; DispatchQueue.main.async { shown = fraction }
            }
            .onChange(of: fraction) { _, value in shown = value }
            .onChange(of: motion) { _, value in if !value { shown = fraction } }
    }
}

/// Small acid-green star beside the 霓虹派对 title.
struct RaveSpark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 20
            ctx.scaleBy(x: s, y: s)
            var p = Path()
            let pts: [(Double, Double)] = [(10, 1), (12, 7), (18, 8), (13, 11), (15, 18), (10, 14), (5, 18), (7, 11), (2, 8), (8, 7)]
            p.move(to: CGPoint(x: pts[0].0, y: pts[0].1)); for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }; p.closeSubpath()
            ctx.stroke(p, with: .color(RavePalette.green), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        }
    }
}
