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

/// Lobe Icons `@lobehub/icons-static-svg@1.95.1` `openrouter.svg` (MIT; SHA256
/// ae671cc83de9bd45db97a47ed5e38a4e1bd9f93a12be495ba4b4f8b284026bca) as native geometry,
/// converted by script (arcs to cubic curves); 24×24 canvas.
struct OpenRouterMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 18.654, y: 3.87))
        p.addCurve(to: CGPoint(x: 23.741, y: 8.957), control1: CGPoint(x: 21.4635, y: 3.87), control2: CGPoint(x: 23.741, y: 6.1475))
        p.addCurve(to: CGPoint(x: 18.654, y: 14.044), control1: CGPoint(x: 23.741, y: 11.7665), control2: CGPoint(x: 21.4635, y: 14.044))
        p.addLine(to: CGPoint(x: 23.7, y: 19.09))
        p.addCurve(to: CGPoint(x: 22.98, y: 20.827), control1: CGPoint(x: 24.34, y: 19.731), control2: CGPoint(x: 23.887, y: 20.827))
        p.addLine(to: CGPoint(x: 8.48, y: 20.827))
        p.addCurve(to: CGPoint(x: 0.001, y: 12.348), control1: CGPoint(x: 3.7972, y: 20.827), control2: CGPoint(x: 0.001, y: 17.0308))
        p.addCurve(to: CGPoint(x: 8.48, y: 3.869), control1: CGPoint(x: 0.001, y: 7.6652), control2: CGPoint(x: 3.7972, y: 3.869))
        p.addLine(to: CGPoint(x: 18.655, y: 3.869))
        p.closeSubpath()
        p.move(to: CGPoint(x: 8.479, y: 7.26))
        p.addCurve(to: CGPoint(x: 3.391, y: 12.348), control1: CGPoint(x: 5.669, y: 7.26), control2: CGPoint(x: 3.391, y: 9.538))
        p.addCurve(to: CGPoint(x: 8.479, y: 17.436), control1: CGPoint(x: 3.391, y: 15.158), control2: CGPoint(x: 5.669, y: 17.436))
        p.addCurve(to: CGPoint(x: 13.5665, y: 12.3485), control1: CGPoint(x: 11.2887, y: 17.436), control2: CGPoint(x: 13.5665, y: 15.1582))
        p.addCurve(to: CGPoint(x: 8.479, y: 7.261), control1: CGPoint(x: 13.5665, y: 9.5388), control2: CGPoint(x: 11.2887, y: 7.261))
        p.closeSubpath()
        return p.applying(PlatformMarkShape.transform(for: rect))
    }
}

/// Lobe Icons `@lobehub/icons-static-svg@1.95.1` `deepseek.svg` (MIT; SHA256
/// 8f9443e351b6dacce71871790201b799d92e8bf96a45ef79aeb5e9bf4db423e2) as native geometry,
/// converted by script (arcs to cubic curves); 24×24 canvas.
struct DeepSeekMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 23.748, y: 4.482))
        p.addCurve(to: CGPoint(x: 23.236, y: 4.716), control1: CGPoint(x: 23.494, y: 4.358), control2: CGPoint(x: 23.384, y: 4.595))
        p.addCurve(to: CGPoint(x: 23.099, y: 4.852), control1: CGPoint(x: 23.185, y: 4.755), control2: CGPoint(x: 23.142, y: 4.806))
        p.addCurve(to: CGPoint(x: 21.726, y: 5.478), control1: CGPoint(x: 22.727, y: 5.249), control2: CGPoint(x: 22.293, y: 5.509))
        p.addCurve(to: CGPoint(x: 19.563, y: 6.326), control1: CGPoint(x: 20.897, y: 5.432), control2: CGPoint(x: 20.189, y: 5.692))
        p.addCurve(to: CGPoint(x: 18.316, y: 4.778), control1: CGPoint(x: 19.43, y: 5.544), control2: CGPoint(x: 18.988, y: 5.078))
        p.addCurve(to: CGPoint(x: 17.361, y: 4.128), control1: CGPoint(x: 17.964, y: 4.622), control2: CGPoint(x: 17.608, y: 4.467))
        p.addCurve(to: CGPoint(x: 17.056, y: 3.354), control1: CGPoint(x: 17.189, y: 3.887), control2: CGPoint(x: 17.142, y: 3.618))
        p.addCurve(to: CGPoint(x: 16.763, y: 3.004), control1: CGPoint(x: 17.001, y: 3.194), control2: CGPoint(x: 16.946, y: 3.031))
        p.addCurve(to: CGPoint(x: 16.407, y: 3.28), control1: CGPoint(x: 16.563, y: 2.973), control2: CGPoint(x: 16.485, y: 3.14))
        p.addCurve(to: CGPoint(x: 15.985, y: 5.12), control1: CGPoint(x: 16.094, y: 3.852), control2: CGPoint(x: 15.973, y: 4.482))
        p.addCurve(to: CGPoint(x: 17.823, y: 8.513), control1: CGPoint(x: 16.012, y: 6.556), control2: CGPoint(x: 16.618, y: 7.7))
        p.addCurve(to: CGPoint(x: 17.952, y: 8.836), control1: CGPoint(x: 17.96, y: 8.606), control2: CGPoint(x: 17.995, y: 8.7))
        p.addCurve(to: CGPoint(x: 17.686, y: 9.669), control1: CGPoint(x: 17.87, y: 9.116), control2: CGPoint(x: 17.772, y: 9.388))
        p.addCurve(to: CGPoint(x: 17.357, y: 9.809), control1: CGPoint(x: 17.631, y: 9.848), control2: CGPoint(x: 17.549, y: 9.886))
        p.addCurve(to: CGPoint(x: 15.621, y: 8.629), control1: CGPoint(x: 16.7083, y: 9.5302), control2: CGPoint(x: 16.119, y: 9.1296))
        p.addCurve(to: CGPoint(x: 13.024, y: 6.171), control1: CGPoint(x: 14.764, y: 7.801), control2: CGPoint(x: 13.99, y: 6.887))
        p.addCurve(to: CGPoint(x: 12.335, y: 5.7), control1: CGPoint(x: 12.8002, y: 6.0056), control2: CGPoint(x: 12.5704, y: 5.8485))
        p.addCurve(to: CGPoint(x: 12.723, y: 3.864), control1: CGPoint(x: 11.35, y: 4.743), control2: CGPoint(x: 12.465, y: 3.957))
        p.addCurve(to: CGPoint(x: 11.944, y: 3.436), control1: CGPoint(x: 12.993, y: 3.766), control2: CGPoint(x: 12.816, y: 3.432))
        p.addCurve(to: CGPoint(x: 9.257, y: 4.12), control1: CGPoint(x: 11.072, y: 3.44), control2: CGPoint(x: 10.274, y: 3.731))
        p.addCurve(to: CGPoint(x: 8.792, y: 4.257), control1: CGPoint(x: 9.1059, y: 4.1779), control2: CGPoint(x: 8.9504, y: 4.2237))
        p.addCurve(to: CGPoint(x: 5.909, y: 4.155), control1: CGPoint(x: 7.8416, y: 4.0779), control2: CGPoint(x: 6.8697, y: 4.0435))
        p.addCurve(to: CGPoint(x: 1.412, y: 6.778), control1: CGPoint(x: 4.024, y: 4.365), control2: CGPoint(x: 2.519, y: 5.257))
        p.addCurve(to: CGPoint(x: 0.152, y: 12.85), control1: CGPoint(x: 0.082, y: 8.606), control2: CGPoint(x: -0.231, y: 10.684))
        p.addCurve(to: CGPoint(x: 3.512, y: 18.503), control1: CGPoint(x: 0.555, y: 15.134), control2: CGPoint(x: 1.721, y: 17.025))
        p.addCurve(to: CGPoint(x: 9.95, y: 20.643), control1: CGPoint(x: 5.37, y: 20.036), control2: CGPoint(x: 7.509, y: 20.787))
        p.addCurve(to: CGPoint(x: 14.944, y: 18.783), control1: CGPoint(x: 11.432, y: 20.558), control2: CGPoint(x: 13.083, y: 20.359))
        p.addCurve(to: CGPoint(x: 16.724, y: 19.18), control1: CGPoint(x: 15.414, y: 19.017), control2: CGPoint(x: 15.906, y: 19.11))
        p.addCurve(to: CGPoint(x: 18.429, y: 19.052), control1: CGPoint(x: 17.354, y: 19.239), control2: CGPoint(x: 17.96, y: 19.15))
        p.addCurve(to: CGPoint(x: 18.848, y: 18.091), control1: CGPoint(x: 19.164, y: 18.896), control2: CGPoint(x: 19.113, y: 18.215))
        p.addCurve(to: CGPoint(x: 16.735, y: 17.165), control1: CGPoint(x: 16.693, y: 17.087), control2: CGPoint(x: 17.166, y: 17.496))
        p.addCurve(to: CGPoint(x: 20.127, y: 10.162), control1: CGPoint(x: 17.831, y: 15.869), control2: CGPoint(x: 19.481, y: 14.523))
        p.addCurve(to: CGPoint(x: 20.127, y: 9.317), control1: CGPoint(x: 20.177, y: 9.815), control2: CGPoint(x: 20.134, y: 9.597))
        p.addCurve(to: CGPoint(x: 20.357, y: 9.061), control1: CGPoint(x: 20.123, y: 9.147), control2: CGPoint(x: 20.162, y: 9.08))
        p.addCurve(to: CGPoint(x: 21.902, y: 8.586), control1: CGPoint(x: 20.898, y: 9.0049), control2: CGPoint(x: 21.4229, y: 8.8435))
        p.addCurve(to: CGPoint(x: 23.995, y: 5.069), control1: CGPoint(x: 23.298, y: 7.823), control2: CGPoint(x: 23.862, y: 6.571))
        p.addCurve(to: CGPoint(x: 23.748, y: 4.481), control1: CGPoint(x: 24.015, y: 4.839), control2: CGPoint(x: 23.991, y: 4.602))
        p.closeSubpath()
        p.move(to: CGPoint(x: 11.581, y: 18))
        p.addCurve(to: CGPoint(x: 8.061, y: 15.84), control1: CGPoint(x: 9.492, y: 16.358), control2: CGPoint(x: 8.479, y: 15.817))
        p.addCurve(to: CGPoint(x: 7.826, y: 16.603), control1: CGPoint(x: 7.669, y: 15.864), control2: CGPoint(x: 7.74, y: 16.311))
        p.addCurve(to: CGPoint(x: 8.197, y: 17.342), control1: CGPoint(x: 7.916, y: 16.891), control2: CGPoint(x: 8.033, y: 17.089))
        p.addCurve(to: CGPoint(x: 8.084, y: 17.945), control1: CGPoint(x: 8.311, y: 17.509), control2: CGPoint(x: 8.389, y: 17.758))
        p.addCurve(to: CGPoint(x: 6.187, y: 17.778), control1: CGPoint(x: 7.411, y: 18.361), control2: CGPoint(x: 6.242, y: 17.805))
        p.addCurve(to: CGPoint(x: 2.886, y: 14.471), control1: CGPoint(x: 4.826, y: 16.976), control2: CGPoint(x: 3.687, y: 15.918))
        p.addCurve(to: CGPoint(x: 1.588, y: 9.989), control1: CGPoint(x: 2.112, y: 13.078), control2: CGPoint(x: 1.662, y: 11.584))
        p.addCurve(to: CGPoint(x: 2.065, y: 9.397), control1: CGPoint(x: 1.568, y: 9.603), control2: CGPoint(x: 1.681, y: 9.467))
        p.addCurve(to: CGPoint(x: 3.594, y: 9.358), control1: CGPoint(x: 2.5691, y: 9.3005), control2: CGPoint(x: 3.0856, y: 9.2874))
        p.addCurve(to: CGPoint(x: 9.062, y: 12.132), control1: CGPoint(x: 5.726, y: 9.67), control2: CGPoint(x: 7.54, y: 10.623))
        p.addCurve(to: CGPoint(x: 11.264, y: 15.023), control1: CGPoint(x: 9.93, y: 12.992), control2: CGPoint(x: 10.587, y: 14.019))
        p.addCurve(to: CGPoint(x: 13.744, y: 17.937), control1: CGPoint(x: 11.984, y: 16.089), control2: CGPoint(x: 12.758, y: 17.105))
        p.addCurve(to: CGPoint(x: 14.635, y: 18.614), control1: CGPoint(x: 14.092, y: 18.229), control2: CGPoint(x: 14.369, y: 18.451))
        p.addCurve(to: CGPoint(x: 11.581, y: 18), control1: CGPoint(x: 13.833, y: 18.704), control2: CGPoint(x: 12.495, y: 18.724))
        p.closeSubpath()
        p.move(to: CGPoint(x: 12.581, y: 11.56))
        p.addCurve(to: CGPoint(x: 12.7129, y: 11.3072), control1: CGPoint(x: 12.5806, y: 11.4592), control2: CGPoint(x: 12.63, y: 11.3646))
        p.addCurve(to: CGPoint(x: 12.996, y: 11.273), control1: CGPoint(x: 12.7959, y: 11.2499), control2: CGPoint(x: 12.9018, y: 11.2371))
        p.addCurve(to: CGPoint(x: 13.196, y: 11.561), control1: CGPoint(x: 13.1173, y: 11.3165), control2: CGPoint(x: 13.1976, y: 11.4322))
        p.addCurve(to: CGPoint(x: 13.1053, y: 11.7795), control1: CGPoint(x: 13.1963, y: 11.643), control2: CGPoint(x: 13.1636, y: 11.7217))
        p.addCurve(to: CGPoint(x: 12.886, y: 11.868), control1: CGPoint(x: 13.047, y: 11.8372), control2: CGPoint(x: 12.968, y: 11.8691))
        p.addCurve(to: CGPoint(x: 12.6693, y: 11.7779), control1: CGPoint(x: 12.8046, y: 11.8683), control2: CGPoint(x: 12.7265, y: 11.8358))
        p.addCurve(to: CGPoint(x: 12.582, y: 11.56), control1: CGPoint(x: 12.6121, y: 11.7199), control2: CGPoint(x: 12.5807, y: 11.6414))
        p.closeSubpath()
        p.move(to: CGPoint(x: 15.691, y: 13.156))
        p.addCurve(to: CGPoint(x: 15.101, y: 13.316), control1: CGPoint(x: 15.491, y: 13.237), control2: CGPoint(x: 15.292, y: 13.307))
        p.addCurve(to: CGPoint(x: 14.303, y: 13.062), control1: CGPoint(x: 14.8137, y: 13.326), control2: CGPoint(x: 14.5317, y: 13.2363))
        p.addCurve(to: CGPoint(x: 13.751, y: 12.304), control1: CGPoint(x: 14.029, y: 12.832), control2: CGPoint(x: 13.833, y: 12.704))
        p.addCurve(to: CGPoint(x: 13.767, y: 11.716), control1: CGPoint(x: 13.7227, y: 12.1085), control2: CGPoint(x: 13.7281, y: 11.9096))
        p.addCurve(to: CGPoint(x: 13.528, y: 10.989), control1: CGPoint(x: 13.837, y: 11.389), control2: CGPoint(x: 13.759, y: 11.179))
        p.addCurve(to: CGPoint(x: 12.84, y: 10.79), control1: CGPoint(x: 13.341, y: 10.833), control2: CGPoint(x: 13.102, y: 10.79))
        p.addCurve(to: CGPoint(x: 12.586, y: 10.712), control1: CGPoint(x: 12.7503, y: 10.7848), control2: CGPoint(x: 12.6632, y: 10.758))
        p.addCurve(to: CGPoint(x: 12.472, y: 10.354), control1: CGPoint(x: 12.476, y: 10.658), control2: CGPoint(x: 12.386, y: 10.522))
        p.addCurve(to: CGPoint(x: 12.664, y: 10.144), control1: CGPoint(x: 12.5, y: 10.3), control2: CGPoint(x: 12.632, y: 10.168))
        p.addCurve(to: CGPoint(x: 13.81, y: 10.16), control1: CGPoint(x: 13.02, y: 9.942), control2: CGPoint(x: 13.431, y: 10.008))
        p.addCurve(to: CGPoint(x: 14.811, y: 10.942), control1: CGPoint(x: 14.162, y: 10.304), control2: CGPoint(x: 14.428, y: 10.568))
        p.addCurve(to: CGPoint(x: 15.496, y: 11.856), control1: CGPoint(x: 15.202, y: 11.393), control2: CGPoint(x: 15.273, y: 11.518))
        p.addCurve(to: CGPoint(x: 15.941, y: 12.704), control1: CGPoint(x: 15.672, y: 12.121), control2: CGPoint(x: 15.832, y: 12.393))
        p.addCurve(to: CGPoint(x: 15.691, y: 13.156), control1: CGPoint(x: 16.008, y: 12.899), control2: CGPoint(x: 15.922, y: 13.058))
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
        switch platform {
        case .codex: OpenAIMarkShape().path(in: rect)
        case .cursor: CursorMarkShape().path(in: rect)
        case .openRouter: OpenRouterMarkShape().path(in: rect)
        case .deepSeek: DeepSeekMarkShape().path(in: rect)
        }
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
