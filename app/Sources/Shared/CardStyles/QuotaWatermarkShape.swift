import SwiftUI

/// Lobe Icons `@lobehub/icons-static-svg@1.95.1` `openai.svg` (MIT; SHA256
/// a595df6b423920c67a7f8f73c063e4bfb72d415948097b6cac063a2366bb5186) as native geometry.
/// The 24×24 source fills its canvas; arcs are converted to cubic curves.
struct OpenAIMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 9.205, y: 8.658))
        p.addLine(to: CGPoint(x: 9.205, y: 6.398))
        p.addCurve(to: CGPoint(x: 9.443, y: 5.97), control1: CGPoint(x: 9.205, y: 6.208), control2: CGPoint(x: 9.277, y: 6.065))
        p.addLine(to: CGPoint(x: 13.986, y: 3.354))
        p.addCurve(to: CGPoint(x: 16.103, y: 2.831), control1: CGPoint(x: 14.605, y: 2.997), control2: CGPoint(x: 15.342, y: 2.831))
        p.addCurve(to: CGPoint(x: 20.765, y: 7.397), control1: CGPoint(x: 18.957, y: 2.831), control2: CGPoint(x: 20.765, y: 5.043))
        p.addCurve(to: CGPoint(x: 20.741, y: 7.944), control1: CGPoint(x: 20.765, y: 7.564), control2: CGPoint(x: 20.765, y: 7.754))
        p.addLine(to: CGPoint(x: 16.031, y: 5.185))
        p.addCurve(to: CGPoint(x: 15.175, y: 5.185), control1: CGPoint(x: 15.7699, y: 5.0188), control2: CGPoint(x: 15.4361, y: 5.0188))
        p.addLine(to: CGPoint(x: 9.205, y: 8.658))
        p.closeSubpath()
        p.move(to: CGPoint(x: 19.814, y: 17.458))
        p.addLine(to: CGPoint(x: 19.814, y: 12.06))
        p.addCurve(to: CGPoint(x: 19.385, y: 11.323), control1: CGPoint(x: 19.814, y: 11.727), control2: CGPoint(x: 19.671, y: 11.49))
        p.addLine(to: CGPoint(x: 13.415, y: 7.85))
        p.addLine(to: CGPoint(x: 15.365, y: 6.732))
        p.addCurve(to: CGPoint(x: 15.841, y: 6.732), control1: CGPoint(x: 15.5094, y: 6.637), control2: CGPoint(x: 15.6966, y: 6.637))
        p.addLine(to: CGPoint(x: 20.384, y: 9.349))
        p.addCurve(to: CGPoint(x: 22.573, y: 13.297), control1: CGPoint(x: 21.693, y: 10.109), control2: CGPoint(x: 22.573, y: 11.727))
        p.addCurve(to: CGPoint(x: 19.813, y: 17.46), control1: CGPoint(x: 22.573, y: 15.105), control2: CGPoint(x: 21.503, y: 16.77))
        p.closeSubpath()
        p.move(to: CGPoint(x: 7.802, y: 12.703))
        p.addLine(to: CGPoint(x: 5.852, y: 11.561))
        p.addCurve(to: CGPoint(x: 5.613, y: 11.133), control1: CGPoint(x: 5.685, y: 11.466), control2: CGPoint(x: 5.613, y: 11.323))
        p.addLine(to: CGPoint(x: 5.613, y: 5.899))
        p.addCurve(to: CGPoint(x: 10.204, y: 1.427), control1: CGPoint(x: 5.613, y: 3.354), control2: CGPoint(x: 7.563, y: 1.427))
        p.addCurve(to: CGPoint(x: 12.916, y: 2.355), control1: CGPoint(x: 11.204, y: 1.427), control2: CGPoint(x: 12.131, y: 1.76))
        p.addLine(to: CGPoint(x: 8.23, y: 5.067))
        p.addCurve(to: CGPoint(x: 7.802, y: 5.804), control1: CGPoint(x: 7.945, y: 5.233), control2: CGPoint(x: 7.802, y: 5.471))
        p.addLine(to: CGPoint(x: 7.802, y: 12.702))
        p.closeSubpath()
        p.move(to: CGPoint(x: 12, y: 15.128))
        p.addLine(to: CGPoint(x: 9.205, y: 13.558))
        p.addLine(to: CGPoint(x: 9.205, y: 10.228))
        p.addLine(to: CGPoint(x: 12, y: 8.658))
        p.addLine(to: CGPoint(x: 14.795, y: 10.228))
        p.addLine(to: CGPoint(x: 14.795, y: 13.558))
        p.addLine(to: CGPoint(x: 12, y: 15.128))
        p.closeSubpath()
        p.move(to: CGPoint(x: 13.796, y: 22.358))
        p.addCurve(to: CGPoint(x: 11.084, y: 21.431), control1: CGPoint(x: 12.796, y: 22.358), control2: CGPoint(x: 11.869, y: 22.026))
        p.addLine(to: CGPoint(x: 15.77, y: 18.719))
        p.addCurve(to: CGPoint(x: 16.198, y: 17.982), control1: CGPoint(x: 16.055, y: 18.553), control2: CGPoint(x: 16.198, y: 18.315))
        p.addLine(to: CGPoint(x: 16.198, y: 11.084))
        p.addLine(to: CGPoint(x: 18.172, y: 12.226))
        p.addCurve(to: CGPoint(x: 18.41, y: 12.654), control1: CGPoint(x: 18.339, y: 12.321), control2: CGPoint(x: 18.41, y: 12.464))
        p.addLine(to: CGPoint(x: 18.41, y: 17.887))
        p.addCurve(to: CGPoint(x: 13.796, y: 22.359), control1: CGPoint(x: 18.41, y: 20.432), control2: CGPoint(x: 16.436, y: 22.359))
        p.closeSubpath()
        p.move(to: CGPoint(x: 8.159, y: 17.055))
        p.addLine(to: CGPoint(x: 3.615, y: 14.438))
        p.addCurve(to: CGPoint(x: 1.427, y: 10.49), control1: CGPoint(x: 2.307, y: 13.677), control2: CGPoint(x: 1.427, y: 12.06))
        p.addCurve(to: CGPoint(x: 4.21, y: 6.327), control1: CGPoint(x: 1.4207, y: 8.6652), control2: CGPoint(x: 2.5214, y: 7.0187))
        p.addLine(to: CGPoint(x: 4.21, y: 11.75))
        p.addCurve(to: CGPoint(x: 4.638, y: 12.488), control1: CGPoint(x: 4.21, y: 12.083), control2: CGPoint(x: 4.353, y: 12.321))
        p.addLine(to: CGPoint(x: 10.585, y: 15.937))
        p.addLine(to: CGPoint(x: 8.635, y: 17.055))
        p.addCurve(to: CGPoint(x: 8.159, y: 17.055), control1: CGPoint(x: 8.4906, y: 17.1503), control2: CGPoint(x: 8.3034, y: 17.1503))
        p.closeSubpath()
        p.move(to: CGPoint(x: 7.897, y: 20.955))
        p.addCurve(to: CGPoint(x: 3.235, y: 16.436), control1: CGPoint(x: 5.209, y: 20.955), control2: CGPoint(x: 3.235, y: 18.934))
        p.addCurve(to: CGPoint(x: 3.282, y: 15.866), control1: CGPoint(x: 3.235, y: 16.246), control2: CGPoint(x: 3.259, y: 16.056))
        p.addLine(to: CGPoint(x: 7.968, y: 18.576))
        p.addCurve(to: CGPoint(x: 8.824, y: 18.576), control1: CGPoint(x: 8.254, y: 18.743), control2: CGPoint(x: 8.539, y: 18.743))
        p.addLine(to: CGPoint(x: 14.794, y: 15.128))
        p.addLine(to: CGPoint(x: 14.794, y: 17.388))
        p.addCurve(to: CGPoint(x: 14.557, y: 17.816), control1: CGPoint(x: 14.794, y: 17.578), control2: CGPoint(x: 14.724, y: 17.721))
        p.addLine(to: CGPoint(x: 10.014, y: 20.432))
        p.addCurve(to: CGPoint(x: 7.897, y: 20.955), control1: CGPoint(x: 9.395, y: 20.789), control2: CGPoint(x: 8.658, y: 20.955))
        p.closeSubpath()
        p.move(to: CGPoint(x: 13.796, y: 23.785))
        p.addCurve(to: CGPoint(x: 19.623, y: 19.029), control1: CGPoint(x: 16.6215, y: 23.7852), control2: CGPoint(x: 19.0571, y: 21.7973))
        p.addCurve(to: CGPoint(x: 24, y: 13.296), control1: CGPoint(x: 22.287, y: 18.339), control2: CGPoint(x: 24, y: 15.84))
        p.addCurve(to: CGPoint(x: 22.002, y: 8.848), control1: CGPoint(x: 24, y: 11.631), control2: CGPoint(x: 23.287, y: 10.014))
        p.addCurve(to: CGPoint(x: 22.192, y: 7.35), control1: CGPoint(x: 22.121, y: 8.348), control2: CGPoint(x: 22.192, y: 7.849))
        p.addCurve(to: CGPoint(x: 16.246, y: 1.403), control1: CGPoint(x: 22.192, y: 3.949), control2: CGPoint(x: 19.433, y: 1.403))
        p.addCurve(to: CGPoint(x: 14.366, y: 1.713), control1: CGPoint(x: 15.604, y: 1.403), control2: CGPoint(x: 14.986, y: 1.498))
        p.addCurve(to: CGPoint(x: 10.205, y: 0), control1: CGPoint(x: 13.256, y: 0.6204), control2: CGPoint(x: 11.7625, y: 0.0056))
        p.addCurve(to: CGPoint(x: 4.378, y: 4.757), control1: CGPoint(x: 7.3792, y: -0.0001), control2: CGPoint(x: 4.9435, y: 1.9883))
        p.addCurve(to: CGPoint(x: 0, y: 10.49), control1: CGPoint(x: 1.713, y: 5.447), control2: CGPoint(x: 0, y: 7.945))
        p.addCurve(to: CGPoint(x: 1.998, y: 14.938), control1: CGPoint(x: 0, y: 12.156), control2: CGPoint(x: 0.713, y: 13.773))
        p.addCurve(to: CGPoint(x: 1.808, y: 16.437), control1: CGPoint(x: 1.879, y: 15.438), control2: CGPoint(x: 1.808, y: 15.938))
        p.addCurve(to: CGPoint(x: 7.754, y: 22.383), control1: CGPoint(x: 1.808, y: 19.838), control2: CGPoint(x: 4.567, y: 22.383))
        p.addCurve(to: CGPoint(x: 9.634, y: 22.074), control1: CGPoint(x: 8.396, y: 22.383), control2: CGPoint(x: 9.014, y: 22.288))
        p.addCurve(to: CGPoint(x: 13.796, y: 23.787), control1: CGPoint(x: 10.7441, y: 23.167), control2: CGPoint(x: 12.2381, y: 23.7819))
        p.closeSubpath()
        return p.applying(PlatformMarkShape.transform(for: rect))
    }
}

/// Lobe Icons `@lobehub/icons-static-svg@1.95.1` `cursor.svg` (MIT; SHA256
/// 0cb51bddf264ae108926fd554c063ef40fc1aac3c5c921ddb39ad184e4e5d0ef), same canvas as the OpenAI mark.
struct CursorMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 22.106, y: 5.68))
        p.addLine(to: CGPoint(x: 12.5, y: 0.135))
        p.addCurve(to: CGPoint(x: 11.502, y: 0.135), control1: CGPoint(x: 12.1912, y: -0.0433), control2: CGPoint(x: 11.8108, y: -0.0433))
        p.addLine(to: CGPoint(x: 1.893, y: 5.68))
        p.addCurve(to: CGPoint(x: 1.474, y: 6.406), control1: CGPoint(x: 1.6339, y: 5.83), control2: CGPoint(x: 1.4743, y: 6.1066))
        p.addLine(to: CGPoint(x: 1.474, y: 17.592))
        p.addCurve(to: CGPoint(x: 1.894, y: 18.319), control1: CGPoint(x: 1.474, y: 17.892), control2: CGPoint(x: 1.634, y: 18.169))
        p.addLine(to: CGPoint(x: 11.501, y: 23.866))
        p.addCurve(to: CGPoint(x: 12.499, y: 23.866), control1: CGPoint(x: 11.8098, y: 24.0441), control2: CGPoint(x: 12.1902, y: 24.0441))
        p.addLine(to: CGPoint(x: 22.107, y: 18.319))
        p.addCurve(to: CGPoint(x: 22.527, y: 17.592), control1: CGPoint(x: 22.3668, y: 18.169), control2: CGPoint(x: 22.5268, y: 17.8919))
        p.addLine(to: CGPoint(x: 22.527, y: 6.407))
        p.addCurve(to: CGPoint(x: 22.107, y: 5.681), control1: CGPoint(x: 22.5265, y: 6.1074), control2: CGPoint(x: 22.3664, y: 5.8308))
        p.closeSubpath()
        p.move(to: CGPoint(x: 21.503, y: 6.856))
        p.addLine(to: CGPoint(x: 12.228, y: 22.92))
        p.addCurve(to: CGPoint(x: 12, y: 22.859), control1: CGPoint(x: 12.165, y: 23.028), control2: CGPoint(x: 12, y: 22.984))
        p.addLine(to: CGPoint(x: 12, y: 12.34))
        p.addCurve(to: CGPoint(x: 11.705, y: 11.83), control1: CGPoint(x: 11.9997, y: 12.1296), control2: CGPoint(x: 11.8873, y: 11.9352))
        p.addLine(to: CGPoint(x: 2.595, y: 6.57))
        p.addCurve(to: CGPoint(x: 2.657, y: 6.342), control1: CGPoint(x: 2.488, y: 6.508), control2: CGPoint(x: 2.532, y: 6.342))
        p.addLine(to: CGPoint(x: 21.207, y: 6.342))
        p.addCurve(to: CGPoint(x: 21.503, y: 6.856), control1: CGPoint(x: 21.471, y: 6.342), control2: CGPoint(x: 21.635, y: 6.628))
        p.closeSubpath()
        return p.applying(PlatformMarkShape.transform(for: rect))
    }
}

/// The platform's own mark: Codex accounts show the OpenAI mark, Cursor accounts the Cursor mark.
/// Lobe marks cut their holes with the even-odd rule, so fills must use `fillStyle`.
struct PlatformMarkShape: Shape {
    let platform: QuotaPlatform
    static let fillStyle = FillStyle(eoFill: true)

    func path(in rect: CGRect) -> Path {
        platform == .cursor ? CursorMarkShape().path(in: rect) : OpenAIMarkShape().path(in: rect)
    }

    static func transform(for rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

/// Which platform mark decorates a card; set by the card from its account.
private struct QuotaPlatformKey: EnvironmentKey { static let defaultValue = QuotaPlatform.codex }
extension EnvironmentValues {
    var quotaPlatform: QuotaPlatform {
        get { self[QuotaPlatformKey.self] }
        set { self[QuotaPlatformKey.self] = newValue }
    }
}
