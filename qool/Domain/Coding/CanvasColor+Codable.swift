/// 合成 `Codable` を使わない理由: 人が読める JSON にする /
/// 欠けたキーを既定値で埋める / 復号時にも不変条件を通す。
nonisolated extension CanvasColor {
    private enum CodingKeys: String, CodingKey {
        case preset
        case custom
    }

    /// プリセット名。`CanvasColor` の case 名と一致させています。
    private enum Preset: String, Codable {
        case paper
        case mint
        case coral
        case sky
        case ink
        case clear
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let preset = try container.decodeIfPresent(Preset.self, forKey: .preset) {
            switch preset {
            case .paper:
                self = .paper
            case .mint:
                self = .mint
            case .coral:
                self = .coral
            case .sky:
                self = .sky
            case .ink:
                self = .ink
            case .clear:
                self = .clear
            }

            return
        }

        self = .custom(try container.decode(RGBAComponents.self, forKey: .custom))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .paper:
            try container.encode(Preset.paper, forKey: .preset)
        case .mint:
            try container.encode(Preset.mint, forKey: .preset)
        case .coral:
            try container.encode(Preset.coral, forKey: .preset)
        case .sky:
            try container.encode(Preset.sky, forKey: .preset)
        case .ink:
            try container.encode(Preset.ink, forKey: .preset)
        case .clear:
            try container.encode(Preset.clear, forKey: .preset)
        case let .custom(components):
            try container.encode(components, forKey: .custom)
        }
    }
}
