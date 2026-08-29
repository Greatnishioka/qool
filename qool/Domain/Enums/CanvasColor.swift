nonisolated enum CanvasColor: Identifiable, Hashable, Codable {
    case paper
    case mint
    case coral
    case sky
    case ink
    case clear
    /// 任意の色。成分は `RGBAComponents` が `0...1` に保つため、
    /// **範囲外や NaN を持つ状態は表現できません。**
    /// 生の `Double` を持っていた頃は、保存時に丸められて往復で値が変わっていました。
    case custom(RGBAComponents)

    var id: String {
        switch self {
        case .paper:
            "paper"
        case .mint:
            "mint"
        case .coral:
            "coral"
        case .sky:
            "sky"
        case .ink:
            "ink"
        case .clear:
            "clear"
        case let .custom(components):
            "custom-\(components.red)-\(components.green)-\(components.blue)-\(components.opacity)"
        }
    }

    /// 色の実体。UI フレームワークには依存しない。
    /// SwiftUI の `Color` への変換は Presentation 層の extension が行う。
    var components: RGBAComponents {
        switch self {
        case .paper:
            RGBAComponents(red: 0.98, green: 0.96, blue: 0.88)
        case .mint:
            RGBAComponents(red: 0.66, green: 0.86, blue: 0.74)
        case .coral:
            RGBAComponents(red: 0.94, green: 0.48, blue: 0.42)
        case .sky:
            RGBAComponents(red: 0.48, green: 0.68, blue: 0.90)
        case .ink:
            RGBAComponents(red: 0.12, green: 0.14, blue: 0.16)
        case .clear:
            RGBAComponents(red: 0, green: 0, blue: 0, opacity: 0)
        case let .custom(components):
            components
        }
    }

    var displayName: String {
        switch self {
        case .paper:
            "紙"
        case .mint:
            "ミント"
        case .coral:
            "コーラル"
        case .sky:
            "スカイ"
        case .ink:
            "インク"
        case .clear:
            "透明"
        case .custom:
            "カスタム"
        }
    }
}
