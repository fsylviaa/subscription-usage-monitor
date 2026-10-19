import SwiftUI

/// Stable catalogue (D-76): 12 compact styles plus 霓虹派对, and 薄荷新拟态 (D-84).
/// The former original style no longer exists; its stored value, a missing value
/// or any unknown value resolves to the default 彩色斜粒 without a write or an error.
enum QuotaCardStyle: String, CaseIterable, Codable, Sendable {
    case skala, capsule, ticks, dials, island, blocks, liquid, ticket, journal, glass, panels, watermark, rave
    /// D-84: soft-UI neumorphism, cream surface and a single low-saturation mint accent.
    case neumorph

    static let defaultStyle = QuotaCardStyle.skala

    var name: String {
        switch self {
        case .skala: "彩色斜粒"
        case .capsule: "薄荷胶囊"
        case .ticks: "精密刻度"
        case .dials: "金色仪表"
        case .island: "黑岛绿线"
        case .blocks: "紫色模块"
        case .liquid: "横向液体"
        case .ticket: "黑白票签"
        case .journal: "暖黄手账"
        case .glass: "冰蓝玻璃"
        case .panels: "橙色双面板"
        case .watermark: "蓝条水印"
        case .rave: "霓虹派对"
        case .neumorph: "薄荷新拟态"
        }
    }

    static func resolve(_ rawValue: String?) -> Self {
        rawValue.flatMap(Self.init(rawValue:)) ?? defaultStyle
    }
}

enum QuotaCardSurface: Sendable {
    case account, detail, smallWidget, mediumWidget

    func motion(reduceMotion: Bool) -> QuotaCardMotion {
        switch self {
        case .smallWidget, .mediumWidget: .staticContent
        case .account, .detail: reduceMotion ? .staticContent : .measuredChanges
        }
    }
}

enum QuotaCardMotion: Sendable { case staticContent, measuredChanges }

/// Derived display input. It never serializes or writes back to the observation.
enum QuotaCardAmount: Equatable, Sendable {
    case unknown, unlimited
    case remaining(Double)
    /// API balance (D-82): a formatted money amount; no ratio, no bar.
    case money(String)

    init(_ amount: QuotaAmount) {
        switch amount {
        case .unknown: self = .unknown
        case .unlimited: self = .unlimited
        case let .limited(value): self = .remaining(value.remaining)
        }
    }

    init(_ amount: WidgetSnapshot.Amount) {
        switch amount {
        case .unknown: self = .unknown
        case .unlimited: self = .unlimited
        case let .limited(used): self = .remaining(100 - used)
        }
    }

    var remainingFraction: Double? {
        guard case let .remaining(value) = self, value.isFinite, (0...100).contains(value) else { return nil }
        return value / 100
    }
}
