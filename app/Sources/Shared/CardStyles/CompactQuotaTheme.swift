import SwiftUI

/// Colours and materials of the approved comparison page (D-74／D-75／D-76,
/// design-references/2026-10-15-紧凑改版, STYLES[].render and SW_PAL).
/// Display only: no storage, no quota semantics.
struct CompactQuotaTheme {
    enum Background {
        case solid(Color)
        /// CSS 135deg: top-left to bottom-right.
        case diagonal([Color])
        /// CSS 160deg, used by 霓虹派对.
        case steep([Color])
        /// radial-gradient(circle at top).
        case radialTop([Color])
        /// Ruled paper: base colour plus a 1pt line every `spacing` points.
        case ruled(base: Color, line: Color, spacing: CGFloat)
    }
    var background: Background
    var ink: Color
    var muted: Color
    var border: Color
    var widgetBorder: Color
    var borderWidth: CGFloat = 1
    var widgetBorderWidth: CGFloat = 1
    var radius: CGFloat = 20
    var watermark: [Color]
    var watermarkOpacity: Double
    /// 霓虹派对 draws a stroked neon outline instead of a filled mark.
    var watermarkOutline = false
}

extension QuotaCardStyle {
    func compactTheme(dark d: Bool, widget: Bool = false) -> CompactQuotaTheme {
        func h(_ light: String, _ dark: String) -> Color { .quotaHex(d ? dark : light) }
        func hs(_ light: [String], _ dark: [String]) -> [Color] { (d ? dark : light).map(Color.quotaHex) }
        let ink = h("24272d", "f5f6f8"), mu = h("68707c", "a9b0b7")
        switch self {
        case .skala:
            return .init(background: .solid(h("fafbfc", "1d1e22")), ink: ink, muted: mu, border: h("d5d9df", "34363b"),
                         widgetBorder: h("d5d9df", "34363b"), watermark: hs(["477da0", "876799", "ba748e"], ["7fcde4", "b688dd", "f57ea5"]),
                         watermarkOpacity: d ? 0.14 : 0.085)
        case .capsule:
            return .init(background: .diagonal(hs(["ffffff", "eaf4ef"], ["2a2d2c", "191c1b"])), ink: ink, muted: mu,
                         border: h("d6e2dc", "3a403d"), widgetBorder: h("d6e2dc", "3a403d"),
                         watermark: hs(["5f9d86", "7fae9a", "6a9c8b"], ["8fd9bf", "a6dcc8", "7cbfa9"]), watermarkOpacity: d ? 0.13 : 0.09)
        case .ticks:
            return .init(background: .solid(h("f9fafb", "101112")), ink: ink, muted: mu, border: h("d9dde3", "2c2e31"),
                         widgetBorder: h("d9dde3", "2c2e31"), watermark: hs(["7f8998", "9aa3b0", "6f7886"], ["c9ced6", "a9b0b7", "e9ebee"]),
                         watermarkOpacity: d ? 0.12 : 0.07)
        case .dials:
            return .init(background: d ? .radialTop(hs([], ["33312d", "17191c"])) : .diagonal(hs(["fffaf0", "efe7d6"], [])),
                         ink: h("24272d", "f3f4f6"), muted: h("8c929b", "a0a5ad"), border: h("e2dacb", "3a3a3a"),
                         widgetBorder: h("e2dacb", "3a3a3a"), watermark: hs(["b58a43", "cfa766", "a87c3a"], ["e6b76b", "f0cd8e", "c9994c"]),
                         watermarkOpacity: d ? 0.11 : 0.08)
        case .island:
            return .init(background: .solid(h("f5f7f2", "1e211f")), ink: h("24272d", "f3f4f6"), muted: h("8c929b", "a9bca8"),
                         border: h("d4dbd1", "3c443e"), widgetBorder: h("d4dbd1", "3c443e"),
                         watermark: hs(["598069", "779883", "638f7c"], ["a5d7b2", "88b99b", "7fa68f"]), watermarkOpacity: d ? 0.12 : 0.085)
        case .blocks:
            return .init(background: .solid(h("eee9f7", "24212c")), ink: h("24272d", "f3f4f6"), muted: mu,
                         border: h("cec1e0", "423a51"), widgetBorder: h("cec1e0", "423a51"),
                         watermark: hs(["7652a2", "9873b2", "836299"], ["c0a0ee", "d6bdf4", "ab8cc8"]), watermarkOpacity: d ? 0.15 : 0.10)
        case .liquid:
            return .init(background: .diagonal(hs(["f2f8f5", "e8f0f2"], ["111831", "090e21"])), ink: h("24272d", "f3f4f6"), muted: mu,
                         border: h("ccdcd8", "2e3954"), widgetBorder: h("ccdcd8", "2e3954"),
                         watermark: hs(["4f947f", "779fac", "679a83"], ["80dcc9", "9ac9b0", "7dacbc"]), watermarkOpacity: d ? 0.14 : 0.095)
        case .ticket:
            return .init(background: .solid(h("fafaf6", "18191b")), ink: h("24272d", "f3f4f6"), muted: h("6d7076", "9a9da3"),
                         border: h("dcdcd6", "3a3c40"), widgetBorder: h("222222", "a3a5a8"), widgetBorderWidth: 2, radius: 12,
                         watermark: hs(["30302d", "555652", "3e4246"], ["e0dfd9", "c1c3c7", "d7d5ce"]), watermarkOpacity: d ? 0.095 : 0.07)
        case .journal:
            return .init(background: .ruled(base: h("fffbeb", "29271f"), line: h("f3ecd0", "333024"), spacing: widget ? 22 : 28),
                         ink: h("24272d", "f3f4f6"), muted: h("737b87", "a9b0b7"), border: h("d6cc9d", "666049"),
                         widgetBorder: h("d6cc9d", "666049"), radius: 12,
                         watermark: hs(["8f772b", "b89b3b", "9f852f"], ["d4b85a", "e4ca71", "f1d985"]), watermarkOpacity: d ? 0.15 : 0.11)
        case .glass:
            return .init(background: .diagonal(hs(["eaf6ff", "d9e8f7"], ["122039", "0c1222"])), ink: h("1f2a3a", "f3f4f6"),
                         muted: h("5f6b7a", "a9b4c2"), border: h("c0d4e4", "385270"), widgetBorder: h("c0d4e4", "385270"),
                         watermark: hs(["4a8fb4", "759ebc", "608caf"], ["94dbf5", "78c5eb", "5bb5df"]), watermarkOpacity: d ? 0.15 : 0.10)
        case .panels:
            return .init(background: .solid(h("f8f5f0", "161718")), ink: h("29231d", "f1f0ed"), muted: h("70665c", "b0b2b7"),
                         border: h("d5cdc3", "4b4e52"), widgetBorder: h("d5cdc3", "4b4e52"),
                         watermark: hs(["a06a3b", "ca9868", "b18055"], ["d58d52", "e7a269", "f4b680"]), watermarkOpacity: d ? 0.115 : 0.085)
        case .watermark:
            return .init(background: .solid(h("fafbfc", "000000")), ink: h("202124", "f4f4f5"), muted: h("6f747c", "929297"),
                         border: h("e6e8eb", "1c1c1e"), widgetBorder: h("e6e8eb", "1c1c1e"),
                         watermark: hs(["202124", "202124"], ["f4f4f5", "f4f4f5"]), watermarkOpacity: d ? 0.12 : 0.06)
        case .rave:
            // Electric blue in both appearances (D-75).
            return .init(background: .steep([.quotaHex("2412ff"), .quotaHex("1807e4")]), ink: .quotaHex("ff6eb0"),
                         muted: .quotaHex("c9ccff"), border: .quotaHex("4335ff"), widgetBorder: .quotaHex("4335ff"),
                         watermark: [.quotaHex("ff2e8b")], watermarkOpacity: 0.22, watermarkOutline: true)
        }
    }
}

/// Neon palette shared by every 霓虹派对 surface.
enum RavePalette {
    static let magenta = Color.quotaHex("ff6eb0")   // readings: 3.11:1 on the brightest blue
    static let laser = Color.quotaHex("ff2e8b")
    static let green = Color.quotaHex("7cff4f")
    static let lilac = Color.quotaHex("c9ccff")
    static let echo = Color.quotaHex("140ba8")      // back layer, same hue family as the ground
    static let shadow = Color.quotaHex("0a0573")
}

struct CompactQuotaBackground: View {
    let style: QuotaCardStyle
    var widget = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch style.compactTheme(dark: scheme == .dark, widget: widget).background {
        case let .solid(color): color
        case let .diagonal(colors): LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        case let .steep(colors): LinearGradient(colors: colors, startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))
        case let .radialTop(colors):
            GeometryReader { g in
                RadialGradient(colors: colors, center: .top, startRadius: 0,
                               endRadius: max(g.size.width, g.size.height))
            }
        case let .ruled(base, line, spacing):
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
                var y = spacing - 1
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(line))
                    y += spacing
                }
            }
        }
    }
}

/// Static, low-contrast mark at the bottom-right corner; never covers readings
/// with contrast and never animates.
struct CompactQuotaWatermark: View {
    let style: QuotaCardStyle
    let base: CGFloat
    let right: CGFloat
    let bottom: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.quotaPlatform) private var platform

    /// D-79: callers keep the original layout values; the Lobe mark is drawn at 75% of them
    /// (corner offsets scale with it) and 2.4× each style's original opacity.
    static let sizeScale: CGFloat = 0.75
    static let opacityScale = 2.4

    init(style: QuotaCardStyle, size: CGFloat, right: CGFloat, bottom: CGFloat) {
        self.style = style
        base = size
        self.right = right * Self.sizeScale
        self.bottom = bottom * Self.sizeScale
    }

    private var size: CGFloat { base * Self.sizeScale }

    var body: some View {
        let theme = style.compactTheme(dark: scheme == .dark)
        GeometryReader { g in
            Group {
                if theme.watermarkOutline {
                    PlatformMarkShape(platform: platform)
                        .stroke(theme.watermark[0], style: StrokeStyle(lineWidth: 1.3 * size / 80, lineJoin: .round))
                } else {
                    PlatformMarkShape(platform: platform)
                        .fill(LinearGradient(colors: theme.watermark, startPoint: .topLeading, endPoint: .bottomTrailing), style: PlatformMarkShape.fillStyle)
                }
            }
            .frame(width: size, height: size)
            // The solid Cursor cube covers more area than the OpenAI line mark; keep it equally faint.
            .opacity(min(1, theme.watermarkOpacity * Self.opacityScale * (platform == .cursor ? 0.6 : 1)))
            .position(x: g.size.width - right - size / 2, y: g.size.height - bottom - size / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
