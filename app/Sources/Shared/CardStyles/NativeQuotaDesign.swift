import SwiftUI

/// Helpers shared by the D-76 card renderer. Display only.
extension Color {
    static func quotaHex(_ hex: String) -> Color {
        let n = UInt32(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
        return Color(.sRGB, red: Double((n >> 16) & 255) / 255,
                     green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255, opacity: 1)
    }
}

/// Forces a still frame (static previews, widgets, reduced motion hosts).
private struct NativeQuotaStaticKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var nativeQuotaStatic: Bool {
        get { self[NativeQuotaStaticKey.self] }
        set { self[NativeQuotaStaticKey.self] = newValue }
    }
}
