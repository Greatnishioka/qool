/// 合成 `Codable` を使わない理由: 人が読める JSON にする /
/// 欠けたキーを既定値で埋める / 復号時にも不変条件を通す。
nonisolated extension RGBAComponents {
    private enum CodingKeys: String, CodingKey {
        case red
        case green
        case blue
        case opacity
    }

    /// 復号値を必ず正規化 `init` に通す。
    /// 合成実装だと格納プロパティへ直接代入されるため、
    /// 手で書き換えられた JSON の NaN や範囲外の値がそのまま入ってしまいます。
    init(from decoder: any Decoder) throws {
        // containerはjsonなのか、plistなのか、yamlなのかを抽象化して読み書きするための機能。
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            red: try container.decode(Double.self, forKey: .red),
            green: try container.decode(Double.self, forKey: .green),
            blue: try container.decode(Double.self, forKey: .blue),
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
        try container.encode(opacity, forKey: .opacity)
    }
}
