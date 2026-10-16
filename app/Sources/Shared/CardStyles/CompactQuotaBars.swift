import SwiftUI

/// Quota graphics of the approved comparison page (render / miniBar / rvBar).
/// The emphasised part always shows what remains and is cut at the exact
/// fraction, so 0%, 100% and decimals stay continuous (D-72／STY-06).
struct CompactQuotaBar: View, @MainActor Animatable {
    let style: QuotaCardStyle
    var fraction: Double
    /// Widget density (smallWidget / mediumWidget miniBar).
    var mini = false
    /// 橙色双面板: the grey 5-hour panel uses its own tick colours.
    var secondary = false
    /// Seconds since a reference, or nil for a still frame (widgets, reduced motion).
    var phase: Double?
    @Environment(\.colorScheme) private var scheme

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    /// Room for glows, the laser tip and the offset shadow outside the layout box.
    private var bleed: CGFloat { style == .rave || style == .island || style == .capsule ? 14 : 0 }

    var body: some View {
        GeometryReader { g in
            Canvas { context, size in
                context.translateBy(x: bleed, y: bleed)
                var painter = CompactBarPainter(context: context, w: g.size.width, h: g.size.height,
                    f: min(max(fraction, 0), 1), dark: scheme == .dark, mini: mini, secondary: secondary, phase: phase)
                painter.draw(style)
            }
            .frame(width: g.size.width + bleed * 2, height: g.size.height + bleed * 2)
            .offset(x: -bleed, y: -bleed)
        }
        .accessibilityHidden(true)
    }
}

struct CompactBarPainter {
    var context: GraphicsContext
    let w: CGFloat
    let h: CGFloat
    let f: Double
    let dark: Bool
    let mini: Bool
    var secondary = false
    let phase: Double?

    private func c(_ light: String, _ dark: String) -> Color { .quotaHex(self.dark ? dark : light) }
    private var fw: CGFloat { w * f }

    mutating func draw(_ style: QuotaCardStyle) {
        switch style {
        case .skala: skala()
        case .capsule: capsule()
        case .ticks: ticks()
        case .dials: break // drawn by CompactDial / CompactMiniGauge
        case .island: island()
        case .blocks: blocks()
        case .liquid: liquid()
        case .ticket: ticket()
        case .journal: journal()
        case .glass: glass()
        case .panels:
            if secondary { panelTicks(on: c("a66e3b", "efb581"), off: c("bcb7b0", "5e6268")) }
            else { panelTicks(on: .quotaHex("352118"), off: .quotaHex("a49a90")) }
        case .watermark: blueBar()
        case .rave: rave()
        }
    }

    /// Paint the whole graphic as used, then the same marks clipped to the
    /// remaining prefix: partial marks are cut exactly at the boundary.
    private func split(_ base: GraphicsContext? = nil, in clip: CGRect? = nil, used: (inout GraphicsContext) -> Void,
                       remaining: (inout GraphicsContext) -> Void) {
        let context = base ?? self.context
        var u = context; used(&u)
        guard f > 0 else { return }
        let area = clip ?? CGRect(x: 0, y: 0, width: w, height: h)
        var r = context
        r.clip(to: Path(CGRect(x: area.minX - 40, y: -40, width: 40 + area.width * f, height: h + 80)))
        remaining(&r)
    }

    // MARK: 彩色斜粒

    private mutating func skala() {
        let cols = ["6fd8b4", "7fcde4", "7d8bdf", "b688dd", "f57ea5", "e9d86d"].map(Color.quotaHex)
        let used = c("c9cfd8", "3c4048")
        let n = mini ? 16 : 28, rows = mini ? 2 : 3
        let x0: CGFloat = mini ? 5 : 6, sy = h / (mini ? 16 : 32)
        let len: CGFloat = mini ? 10 : 12, thick: CGFloat = mini ? 3.6 : 4.4
        func grain(_ col: Int, _ row: Int) -> Path {
            let x = x0 + CGFloat(col) * (w - x0 * 2) / CGFloat(n - 1)
            let y = ((mini ? 4 : 6) + CGFloat(row) * (mini ? 8 : 10)) * sy
            return Path(roundedRect: CGRect(x: -len / 2, y: -thick / 2, width: len, height: thick), cornerRadius: thick / 2)
                .applying(CGAffineTransform(rotationAngle: .pi / 4).concatenating(CGAffineTransform(translationX: x, y: y)))
        }
        split(used: { ctx in
            for col in 0..<n { for row in 0..<rows { ctx.fill(grain(col, row), with: .color(used)) } }
        }, remaining: { ctx in
            for col in 0..<n { for row in 0..<rows { ctx.fill(grain(col, row), with: .color(cols[(col + row * 2) % 6])) } }
        })
    }

    // MARK: 薄荷胶囊（果冻凝胶）

    private mutating func capsule() {
        let r = h / 2
        let track = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: r)
        context.fill(track, with: .color(c("dfe8e3", "343a37")))
        var inside = context; inside.clip(to: track)
        // Empty shell: inset shade plus diagonal stripes.
        inside.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.45)),
                    with: .linearGradient(Gradient(colors: [.black.opacity(0.14), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.45)))
        let band: CGFloat = 4 * 1.414, pitch: CGFloat = 10 * 1.414
        var stripes = Path(); var x = -h
        while x < w + h {
            stripes.move(to: CGPoint(x: x, y: 0)); stripes.addLine(to: CGPoint(x: x + band, y: 0))
            stripes.addLine(to: CGPoint(x: x + band - h, y: h)); stripes.addLine(to: CGPoint(x: x - h, y: h)); stripes.closeSubpath()
            x += pitch
        }
        inside.fill(stripes, with: .color(.white.opacity(dark ? 0.09 : 0.35)))
        inside.fill(Path(CGRect(x: r, y: h - 1, width: max(0, w - h), height: 1)), with: .color(.white.opacity(dark ? 0.15 : 0.6)))
        guard f > 0 else { return }
        let gelRect = CGRect(x: 0, y: 0, width: fw, height: h)
        let gel = Path(roundedRect: gelRect, cornerRadius: min(r, fw / 2))
        if !mini {
            var glow = context
            glow.addFilter(.blur(radius: 6))
            glow.fill(gel.offsetBy(dx: 0, dy: 4), with: .color(Color.quotaHex("3fd3a3").opacity(0.45)))
        }
        context.fill(gel, with: .linearGradient(Gradient(stops: [
            .init(color: .quotaHex("d6fdf0"), location: 0), .init(color: .quotaHex("86f2cf"), location: 0.38),
            .init(color: .quotaHex("3fd3a3"), location: 1)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        var g = context; g.clip(to: gel)
        g.fill(Path(CGRect(x: 0, y: h * 0.5, width: fw, height: h * 0.5)),
               with: .linearGradient(Gradient(colors: [.clear, Color.quotaHex("148c64").opacity(0.35)]),
                                     startPoint: CGPoint(x: 0, y: h * 0.5), endPoint: CGPoint(x: 0, y: h)))
        let hl = mini ? CGRect(x: 5, y: 2, width: fw - 13, height: 4) : CGRect(x: 8, y: 3, width: fw - 22, height: 7)
        if hl.width > 0 {
            g.fill(Path(roundedRect: hl, cornerRadius: hl.height / 2), with: .linearGradient(
                Gradient(colors: [.white.opacity(0.95), .white.opacity(0.15)]), startPoint: CGPoint(x: 0, y: hl.minY), endPoint: CGPoint(x: 0, y: hl.maxY)))
        }
        let edge = mini ? CGRect(x: fw - 5, y: 3, width: 3, height: h - 6) : CGRect(x: fw - 9, y: 4, width: 6, height: h - 8)
        if edge.minX > 0 { g.fill(Path(roundedRect: edge, cornerRadius: edge.width / 2), with: .color(.white.opacity(0.55))) }
        guard !mini else { return }
        // Three small bubbles; they sway gently in the App (CSS 'bub', 3.2s).
        for (i, b) in [(0.18, 11.0, 6.0), (0.46, 13.0, 4.0), (0.71, 10.0, 5.0)].enumerated() {
            var dx = 0.0, dy = 0.0
            if let phase {
                let t = ((phase + Double(i)) / 3.2).truncatingRemainder(dividingBy: 1)
                let k = (1 - cos(2 * .pi * t)) / 2
                dx = 6 * k; dy = -3 * k
            }
            let rect = CGRect(x: fw * b.0 + dx, y: b.1 * h / 26 + dy, width: b.2, height: b.2)
            g.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.75)))
        }
    }

    // MARK: 精密刻度

    private mutating func ticks() {
        let n = mini ? 34 : 60
        context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: mini ? 2 : 3),
                     with: .color(c("e9ecf0", "1d1e21")))
        let width: CGFloat = mini ? 1.8 : 2.2, inset: CGFloat = mini ? 0.8 : 1
        let minorTop = h * (mini ? 3.0 / 16 : 4.0 / 30)
        func marks(_ ctx: inout GraphicsContext, _ color: Color) {
            for i in 0..<n {
                let x = CGFloat(i) * w / CGFloat(n) + inset
                let major = i % 5 == 0
                ctx.fill(Path(CGRect(x: x, y: major ? 0 : minorTop, width: width, height: major ? h : h - minorTop)), with: .color(color))
            }
        }
        let on = c("262b33", "f4f5f7"), off = c("b9c0ca", "4a4e55")
        split(used: { marks(&$0, off) }, remaining: { marks(&$0, on) })
    }

    // MARK: 黑岛绿线

    private mutating func island() {
        let track = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: h / 2)
        context.fill(track, with: .color(.quotaHex("505650")))
        guard f > 0 else { return }
        let line = Path(roundedRect: CGRect(x: 0, y: 0, width: fw, height: h), cornerRadius: min(h / 2, fw / 2))
        if !mini {
            var glow = context; glow.addFilter(.blur(radius: 5))
            glow.fill(line, with: .color(Color.quotaHex("a5f28b").opacity(0.55)))
        }
        context.fill(line, with: .color(.quotaHex("a5f28b")))
    }

    // MARK: 紫色模块

    private mutating func blocks() {
        let gap: CGFloat = mini ? 4 : 6, radius: CGFloat = mini ? 5 : 9
        let seg = (w - gap * 4) / 5
        let acc = c("9366cc", "b394ed"), used = c("cec6da", "4c435b")
        for i in 0..<5 {
            let rect = CGRect(x: CGFloat(i) * (seg + gap), y: 0, width: seg, height: h)
            let shape = Path(roundedRect: rect, cornerRadius: radius)
            context.fill(shape, with: .color(used))
            let k = min(1, max(0, f * 5 - Double(i)))
            if k > 0 {
                var s = context; s.clip(to: shape)
                s.fill(Path(CGRect(x: rect.minX, y: 0, width: seg * k, height: h)), with: .color(acc))
            }
        }
    }

    // MARK: 横向液体

    private mutating func liquid() {
        let border: CGFloat = mini ? 1.2 : 1.5, pad: CGFloat = mini ? 2 : 4
        let outer = CGRect(x: 0, y: 0, width: w, height: h)
        let shell = Path(roundedRect: outer.insetBy(dx: border / 2, dy: border / 2), cornerRadius: mini ? 7 : 14)
        context.fill(shell, with: .color(c("e8f0ed", "151d31")))
        context.stroke(shell, with: .color(c("80958d", "818f9f")), lineWidth: border)
        let inner = outer.insetBy(dx: border + pad, dy: border + pad)
        let room = Path(roundedRect: inner, cornerRadius: mini ? 5 : 9)
        context.fill(room, with: .color(c("b5c2c0", "3b4652")))
        guard f > 0 else { return }
        var g = context; g.clip(to: room)
        let body = CGRect(x: inner.minX, y: inner.minY, width: inner.width * f, height: inner.height)
        g.fill(Path(body), with: .linearGradient(Gradient(stops: [
            .init(color: .quotaHex("93f47e"), location: 0), .init(color: .quotaHex("48c570"), location: 0.55),
            .init(color: .quotaHex("187b63"), location: 1)]), startPoint: CGPoint(x: 0, y: inner.minY), endPoint: CGPoint(x: 0, y: inner.maxY)))
        guard !mini else { return }
        g.clip(to: Path(body))
        g.fill(Path(CGRect(x: body.minX, y: inner.minY + 4, width: body.width, height: 4)), with: .color(.white.opacity(0.18)))
        for (x, y, s, o) in [(0.18, 0.55, 5.0, 0.35), (0.52, 0.30, 4.0, 0.3)] {
            g.fill(Path(ellipseIn: CGRect(x: body.minX + body.width * x, y: inner.minY + inner.height * y, width: s, height: s)),
                   with: .color(Color.quotaHex("ddffd3").opacity(o)))
        }
    }

    // MARK: 黑白票签

    private mutating func ticket() {
        let border: CGFloat = mini ? 1.5 : 2, radius: CGFloat = mini ? 3 : 5
        let frame = CGRect(x: 0, y: 0, width: w, height: h)
        let shape = Path(roundedRect: frame.insetBy(dx: border / 2, dy: border / 2), cornerRadius: radius)
        context.fill(shape, with: .color(c("eeeeee", "27292d")))
        let content = frame.insetBy(dx: border, dy: border)
        let vw: CGFloat = mini ? 142 : 244, vh: CGFloat = mini ? 16 : 30
        let sx = content.width / vw, sy = content.height / vh
        func pieces(_ ctx: inout GraphicsContext, _ color: Color) {
            var p = Path()
            for i in -1..<(mini ? 17 : 26) {
                let x = CGFloat(i) * (mini ? 9 : 9.5)
                let (a, b, top, bottom): (CGFloat, CGFloat, CGFloat, CGFloat) = mini ? (5, 5, 2, 14) : (6, 6, 3, 27)
                p.move(to: CGPoint(x: content.minX + (x + a) * sx, y: content.minY + top * sy))
                p.addLine(to: CGPoint(x: content.minX + (x + a + b) * sx, y: content.minY + top * sy))
                p.addLine(to: CGPoint(x: content.minX + (x + b) * sx, y: content.minY + bottom * sy))
                p.addLine(to: CGPoint(x: content.minX + x * sx, y: content.minY + bottom * sy))
                p.closeSubpath()
            }
            ctx.fill(p, with: .color(color))
        }
        var inner = context; inner.clip(to: Path(roundedRect: content, cornerRadius: max(0, radius - border)))
        split(inner, in: content, used: { pieces(&$0, c("b8b8b4", "6c6f74")) }, remaining: { pieces(&$0, c("161616", "f5f5f0")) })
        context.stroke(shape, with: .color(c("202020", "d9dcdf")), lineWidth: border)
    }

    // MARK: 暖黄手账

    private mutating func journal() {
        let border: CGFloat = mini ? 2 : 3
        let frame = CGRect(x: 0, y: 0, width: w, height: h)
        let content = frame.insetBy(dx: border, dy: border)
        let vw: CGFloat = mini ? 142 : 350, vh: CGFloat = mini ? 16 : 32
        // SVG 'meet': one uniform scale, centred, leaving paper margins at both ends.
        let s = min(content.width / vw, content.height / vh)
        let ox = content.minX + (content.width - vw * s) / 2, oy = content.minY + (content.height - vh * s) / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        func strokes(_ ctx: inout GraphicsContext, _ color: Color) {
            var p = Path()
            let n = mini ? 15 : 26
            for i in 0..<n {
                if mini {
                    let x = 3 + CGFloat(i) * 136 / 15, d = CGFloat(i % 3) * 0.5
                    p.move(to: pt(x + 2, 3 + d)); p.addQuadCurve(to: pt(x + 2, 13 + d), control: pt(x, 8 + d))
                    p.addLine(to: pt(x + 7, 13 + d)); p.addQuadCurve(to: pt(x + 7, 3 + d), control: pt(x + 9, 8 + d))
                } else {
                    let x = 4 + CGFloat(i) * 342 / 26, d = CGFloat(i % 3), lift: CGFloat = i % 3 == 1 ? 1 : 0
                    p.move(to: pt(x + 2, 5 + d)); p.addQuadCurve(to: pt(x + 2, 27 + d), control: pt(x - 1, 16 + d))
                    p.addLine(to: pt(x + 9, 27 + d - lift)); p.addQuadCurve(to: pt(x + 9, 5 + d - lift), control: pt(x + 12, 16 + d - lift))
                }
                p.closeSubpath()
            }
            ctx.fill(p, with: .color(color))
        }
        split(in: CGRect(x: ox, y: content.minY, width: vw * s, height: content.height), used: { strokes(&$0, c("ceccbf", "646254")) }, remaining: { strokes(&$0, c("d2ad2d", "e6c954")) })
        // Hand-drawn frame: slightly uneven corners.
        let r: CGFloat = mini ? 6 : 11
        context.stroke(Path(roundedRect: frame.insetBy(dx: border / 2, dy: border / 2), cornerSize: CGSize(width: r + 2, height: r)),
                       with: .color(c("c4a12d", "c6ae55")), lineWidth: border)
    }

    // MARK: 冰蓝玻璃（冰晶试管）

    private mutating func glass() {
        let border: CGFloat = mini ? 1.2 : 1.5
        let frame = CGRect(x: 0, y: 0, width: w, height: h)
        let tube = Path(roundedRect: frame.insetBy(dx: border / 2, dy: border / 2), cornerRadius: h / 2)
        context.fill(tube, with: .linearGradient(Gradient(colors: dark
            ? [Color(.sRGB, red: 120 / 255, green: 150 / 255, blue: 190 / 255, opacity: 0.35), Color(.sRGB, red: 60 / 255, green: 80 / 255, blue: 110 / 255, opacity: 0.5)]
            : [.white.opacity(0.75), Color(.sRGB, red: 205 / 255, green: 222 / 255, blue: 240 / 255, opacity: 0.55)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        var g = context; g.clip(to: tube)
        // Frosted surface.
        var frost = Path()
        for (sx, sy, ox, oy, r) in [(11.0, 9.0, 0.0, 0.0, 0.9), (7.0, 13.0, 4.0, 3.0, 0.7)] {
            var y = oy; while y < Double(h) { var x = ox; while x < Double(w) { frost.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)); x += sx }; y += sy }
        }
        g.fill(frost, with: .color(.white.opacity(0.5)))
        g.fill(Path(CGRect(x: 0, y: 0, width: w, height: 5)), with: .linearGradient(
            Gradient(colors: [Color.quotaHex("4678aa").opacity(0.18), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 5)))
        if f > 0 {
            let liquidGradient = GraphicsContext.Shading.linearGradient(Gradient(stops: [
                .init(color: .quotaHex("bdeeff"), location: 0), .init(color: .quotaHex("5cc8ff"), location: 0.3),
                .init(color: .quotaHex("2f7fe8"), location: 0.75), .init(color: .quotaHex("2563c9"), location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h))
            if mini {
                g.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: fw, height: h), cornerRadius: min(6, fw / 2)), with: liquidGradient)
            } else {
                // Meniscus: a curved front whose outermost point sits exactly at the fraction.
                let span = min(9.5, fw), body = max(0, fw - span)
                let s = span / 9.5, k = h / 32
                var front = Path()
                front.move(to: CGPoint(x: body, y: 0))
                front.addCurve(to: CGPoint(x: body + 9 * s, y: 16 * k), control1: CGPoint(x: body + 10 * s, y: 6 * k), control2: CGPoint(x: body + 2 * s, y: 12 * k))
                front.addCurve(to: CGPoint(x: body, y: h), control1: CGPoint(x: body + 2 * s, y: 20 * k), control2: CGPoint(x: body + 10 * s, y: 26 * k))
                front.closeSubpath()
                if body > 0 { g.fill(Path(CGRect(x: 0, y: 0, width: body + 0.5, height: h)), with: liquidGradient) }
                g.fill(front, with: .color(.quotaHex("3d90ee")))
                var bubbles = g
                bubbles.clip(to: Path(CGRect(x: 0, y: 0, width: fw, height: h)))
                for (i, b) in [(0.22, 14.0, 5.0), (0.55, 16.0, 4.0), (0.80, 12.0, 6.0)].enumerated() {
                    var dy = 0.0, opacity = 1.0
                    if let phase {
                        // CSS 'rise' (2.8s): fade in, drift up and fade out.
                        let t = ((phase + Double(i) * 0.9) / 2.8).truncatingRemainder(dividingBy: 1)
                        let e = t * t
                        dy = 8 - 18 * e
                        opacity = t < 0.3 ? t / 0.3 : 1 - (t - 0.3) / 0.7
                    }
                    let rect = CGRect(x: fw * b.0 - b.2 / 2, y: b.1 * k + dy - b.2 / 2, width: b.2, height: b.2)
                    bubbles.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.25 * opacity)))
                    bubbles.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.85 * opacity)), lineWidth: 1)
                }
            }
        }
        if !mini {
            for k in 1...10 {
                let x = CGFloat(k) * w / 10 - 1
                g.fill(Path(CGRect(x: x, y: h * 0.62, width: 1, height: h * 0.2)), with: .color(.white.opacity(0.75)))
            }
        }
        let shine = mini ? CGRect(x: 6, y: 2, width: w - 12, height: 2) : CGRect(x: 10, y: 5, width: w - 20, height: 4)
        g.fill(Path(roundedRect: shine, cornerRadius: shine.height / 2), with: .color(.white.opacity(0.75)))
        context.stroke(tube, with: .color(dark ? Color(.sRGB, red: 137 / 255, green: 204 / 255, blue: 239 / 255, opacity: 0.75)
                                             : Color(.sRGB, red: 96 / 255, green: 159 / 255, blue: 207 / 255, opacity: 0.75)), lineWidth: border)
    }

    // MARK: 橙色双面板 tick rows

    mutating func panelTicks(on: Color, off: Color) {
        let n = mini ? 24 : 40, unit: CGFloat = mini ? 142 : 350
        let pitch: CGFloat = mini ? 5.9 : 8.75, bar: CGFloat = mini ? 3 : 4.4, radius: CGFloat = mini ? 1 : 1.5
        let s = w / unit
        func marks(_ ctx: inout GraphicsContext, _ color: Color) {
            var p = Path()
            for i in 0..<n { p.addRoundedRect(in: CGRect(x: CGFloat(i) * pitch * s, y: 0, width: bar * s, height: h), cornerSize: CGSize(width: radius, height: radius)) }
            ctx.fill(p, with: .color(color))
        }
        split(used: { marks(&$0, off) }, remaining: { marks(&$0, on) })
    }

    // MARK: 蓝条水印

    private mutating func blueBar() {
        let r = h / 2
        context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: r), with: .color(c("e0e3e7", "292929")))
        guard f > 0 else { return }
        context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: fw, height: h), cornerRadius: min(r, fw / 2)), with: .color(.quotaHex("329eff")))
    }

    // MARK: 霓虹派对 laser beam

    private mutating func rave() {
        let r = h / 2
        let groove = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: r)
        context.fill(groove, with: .color(.quotaHex("0b0680")))
        var g = context; g.clip(to: groove)
        g.fill(Path(CGRect(x: 0, y: 0, width: w, height: min(5, h / 2))), with: .linearGradient(
            Gradient(colors: [.black.opacity(0.55), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: min(5, h / 2))))
        g.fill(Path(CGRect(x: r, y: h - 1, width: max(0, w - h), height: 1)), with: .color(Color(.sRGB, red: 120 / 255, green: 110 / 255, blue: 1, opacity: 0.35)))
        var dots = Path(); var x: CGFloat = 4.5
        while x < w { dots.addEllipse(in: CGRect(x: x - 1.2, y: h / 2 - 1.2, width: 2.4, height: 2.4)); x += 9 }
        g.fill(dots, with: .color(Color(.sRGB, red: 201 / 255, green: 204 / 255, blue: 1, opacity: 0.45)))
        var ticks = Path()
        for k in 1...10 { ticks.addRect(CGRect(x: CGFloat(k) * w / 10 - 2, y: h * 0.3, width: 2, height: h * 0.4)) }
        g.fill(ticks, with: .color(RavePalette.green.opacity(0.9)))
        guard f > 0 else { return }
        // Offset dark layer, the beam with its glow, white-hot core, sweep, tip.
        context.fill(Path(roundedRect: CGRect(x: 4, y: 5, width: fw, height: h), cornerRadius: min(r, fw / 2)), with: .color(.quotaHex("07035a")))
        let beam = Path(roundedRect: CGRect(x: 0, y: 0, width: fw, height: h), cornerRadius: min(r, fw / 2))
        for (radius, alpha) in [(13.0, 0.55), (5.0, 0.95)] {
            var glow = context; glow.addFilter(.blur(radius: radius / 2))
            glow.fill(beam, with: .color(RavePalette.laser.opacity(alpha)))
        }
        context.fill(beam, with: .linearGradient(Gradient(stops: [
            .init(color: .quotaHex("ff9ccd"), location: 0), .init(color: .quotaHex("ff2e8b"), location: 0.38),
            .init(color: .quotaHex("ff2e8b"), location: 0.62), .init(color: .quotaHex("c8006a"), location: 1)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        if fw > 12 {
            let core = Path(roundedRect: CGRect(x: 6, y: h / 2 - 1, width: fw - 12, height: 2), cornerRadius: 1)
            var glow = context; glow.addFilter(.blur(radius: 3))
            glow.fill(core, with: .color(Color.quotaHex("ffd1e8")))
            context.fill(core, with: .color(.white))
        }
        var pulse = 0.0
        if let phase {
            var sweep = context; sweep.clip(to: beam)
            let t = (phase / 2.6).truncatingRemainder(dividingBy: 1)
            let bw = fw * 0.4, sx = -bw + (fw * 1.6) * t
            sweep.fill(Path(CGRect(x: sx, y: 0, width: bw, height: h)), with: .linearGradient(
                Gradient(colors: [.clear, .white.opacity(0.55), .clear]), startPoint: CGPoint(x: sx, y: 0), endPoint: CGPoint(x: sx + bw, y: 0)))
            pulse = (1 - cos(2 * .pi * (phase / 1.6).truncatingRemainder(dividingBy: 1))) / 2
        }
        let tipH = h + 8, tip = Path(roundedRect: CGRect(x: fw - 2.5, y: h / 2 - tipH / 2, width: 5, height: tipH), cornerRadius: 2.5)
        let halo: [(CGFloat, Color)] = [
            (CGFloat(30 + 10 * pulse), RavePalette.laser.opacity(0.6 + 0.1 * pulse)),
            (CGFloat(18 + 8 * pulse), RavePalette.laser.opacity(0.95)),
            (CGFloat(10 + 4 * pulse), Color.quotaHex("ff9ccd")),
            (CGFloat(4 + 2 * pulse), Color.white)]
        for (radius, color) in halo {
            var glow = context; glow.addFilter(.blur(radius: radius / 3))
            glow.fill(tip, with: .color(color))
        }
        context.fill(tip, with: .color(.white))
    }
}

/// 金色仪表 card dial: E→F retro fuel gauge (comparison page dial()).
/// The needle shows `fraction`; the number is laid out by the caller.
struct CompactDial: View, @MainActor Animatable {
    var fraction: Double
    @Environment(\.colorScheme) private var scheme
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let s = min(size.width / 160, size.height / 150)
            context.translateBy(x: (size.width - 160 * s) / 2, y: (size.height - 150 * s) / 2)
            context.scaleBy(x: s, y: s)
            Self.draw(&context, f: min(max(fraction, 0), 1), dark: scheme == .dark)
        }
        .accessibilityHidden(true)
    }

    static func draw(_ ctx: inout GraphicsContext, f: Double, dark: Bool) {
        let cx = 80.0, cy = 74.0, r = 56.0, a0 = 150.0, sweep = 240.0
        func pt(_ a: Double, _ rr: Double) -> CGPoint { CGPoint(x: cx + rr * cos(a * .pi / 180), y: cy + rr * sin(a * .pi / 180)) }
        func arc(_ from: Double, _ to: Double, _ rr: Double) -> Path {
            var p = Path(); p.addArc(center: CGPoint(x: cx, y: cy), radius: rr, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false); return p
        }
        let ring = Gradient(stops: [.init(color: .quotaHex("fbe6ae"), location: 0), .init(color: .quotaHex("c18a2e"), location: 0.45),
                                    .init(color: .quotaHex("f3d07c"), location: 0.7), .init(color: .quotaHex("9c6a1f"), location: 1)])
        let face = Path(ellipseIn: CGRect(x: cx - r - 9, y: cy - r - 9, width: (r + 9) * 2, height: (r + 9) * 2))
        ctx.fill(face, with: .radialGradient(Gradient(colors: dark ? [.quotaHex("3a3732"), .quotaHex("1d1c1a")] : [.quotaHex("fffdf6"), .quotaHex("efe3c8")]),
                                             center: CGPoint(x: cx, y: cy - 0.12 * (r + 9) * 2), startRadius: 0, endRadius: (r + 9) * 1.4))
        ctx.stroke(face, with: .linearGradient(ring, startPoint: CGPoint(x: cx - r - 9, y: cy - r - 9), endPoint: CGPoint(x: cx + r + 9, y: cy + r + 9)), lineWidth: 5)
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - r - 5.5, y: cy - r - 5.5, width: (r + 5.5) * 2, height: (r + 5.5) * 2)), with: .color(.black.opacity(0.08)), lineWidth: 1)
        let round = StrokeStyle(lineWidth: 7, lineCap: .round)
        ctx.stroke(arc(a0, a0 + sweep, r - 4), with: .color(.quotaHex(dark ? "45423d" : "ddd4c3")), style: round)
        ctx.stroke(arc(a0, a0 + sweep * 0.15, r - 4), with: .color(Color.quotaHex("e0533f").opacity(0.85)), style: round)
        let e = a0 + sweep * f
        if f > 0 {
            var glow = ctx; glow.addFilter(.shadow(color: Color(.sRGB, red: 230 / 255, green: 170 / 255, blue: 60 / 255, opacity: 0.7), radius: 3))
            glow.stroke(arc(a0, e, r - 4), with: .linearGradient(Gradient(colors: [.quotaHex("e2a83f"), .quotaHex("ffd66e")]),
                        startPoint: CGPoint(x: cx - r, y: cy + r), endPoint: CGPoint(x: cx + r, y: cy - r)), style: round)
        }
        for i in 0...20 {
            let a = a0 + sweep * Double(i) / 20
            var p = Path(); p.move(to: pt(a, r - 11)); p.addLine(to: pt(a, r - (i % 5 == 0 ? 19 : 15)))
            ctx.stroke(p, with: .color(.quotaHex(dark ? "9a9080" : "8a7a5c")), style: StrokeStyle(lineWidth: i % 5 == 0 ? 1.8 : 1, lineCap: .round))
        }
        let eLabel = pt(a0 - 14, r - 8), fLabel = pt(a0 + sweep + 14, r - 8)
        ctx.draw(Text("E").font(.system(size: 11, weight: .heavy)).foregroundColor(.quotaHex("d24a36")), at: eLabel)
        ctx.draw(Text("F").font(.system(size: 11, weight: .heavy)).foregroundColor(.quotaHex(dark ? "e6b76b" : "8a6a2a")), at: fLabel)
        var needle = Path()
        needle.move(to: pt(e, r - 14)); needle.addLine(to: pt(e + 90, 3.2)); needle.addLine(to: pt(e + 180, 9)); needle.addLine(to: pt(e - 90, 3.2)); needle.closeSubpath()
        var shadowed = ctx; shadowed.addFilter(.shadow(color: .black.opacity(0.35), radius: 1.5, x: 1, y: 2))
        shadowed.fill(needle, with: .color(.quotaHex(dark ? "ff6a4d" : "b2321f")))
        let hub = Path(ellipseIn: CGRect(x: cx - 7, y: cy - 7, width: 14, height: 14))
        shadowed.fill(hub, with: .linearGradient(ring, startPoint: CGPoint(x: cx - 7, y: cy - 7), endPoint: CGPoint(x: cx + 7, y: cy + 7)))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 2.4, y: cy - 2.4, width: 4.8, height: 4.8)), with: .color(.quotaHex(dark ? "2a2010" : "6b4a14")))
    }
}

/// 金色仪表 widget gauge (comparison page miniGauge(), 68×62).
struct CompactMiniGauge: View {
    let fraction: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 68, size.height / 62)
            ctx.translateBy(x: (size.width - 68 * s) / 2, y: (size.height - 62 * s) / 2)
            ctx.scaleBy(x: s, y: s)
            let dark = scheme == .dark, f = min(max(fraction, 0), 1)
            let cx = 34.0, cy = 32.0, r = 26.0, a0 = 150.0, sweep = 240.0
            func arc(_ from: Double, _ to: Double) -> Path {
                var p = Path(); p.addArc(center: CGPoint(x: cx, y: cy), radius: r - 2, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false); return p
            }
            let face = Path(ellipseIn: CGRect(x: cx - r - 4, y: cy - r - 4, width: (r + 4) * 2, height: (r + 4) * 2))
            ctx.fill(face, with: .color(.quotaHex(dark ? "2b2925" : "fffaf0")))
            ctx.stroke(face, with: .color(.quotaHex("c99a3e")), lineWidth: 2.5)
            let round = StrokeStyle(lineWidth: 4, lineCap: .round)
            ctx.stroke(arc(a0, a0 + sweep), with: .color(.quotaHex(dark ? "45423d" : "ddd4c3")), style: round)
            ctx.stroke(arc(a0, a0 + sweep * 0.15), with: .color(.quotaHex("e0533f")), style: round)
            let e = a0 + sweep * f
            if f > 0 { ctx.stroke(arc(a0, e), with: .color(.quotaHex("e2a83f")), style: round) }
            var needle = Path(); needle.move(to: CGPoint(x: cx, y: cy))
            needle.addLine(to: CGPoint(x: cx + (r - 7) * cos(e * .pi / 180), y: cy + (r - 7) * sin(e * .pi / 180)))
            ctx.stroke(needle, with: .color(.quotaHex(dark ? "ff6a4d" : "b2321f")), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 3.2, y: cy - 3.2, width: 6.4, height: 6.4)), with: .color(.quotaHex("c99a3e")))
        }
        .accessibilityHidden(true)
    }
}
