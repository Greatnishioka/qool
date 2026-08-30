/// 合成 `Codable` を使わない理由: 人が読める JSON にする /
/// 欠けたキーを既定値で埋める / 復号時にも不変条件を通す。
nonisolated extension ImageAdjustment {
    private enum CodingKeys: String, CodingKey {
        case opacity
        case brightness
        case padding
        case blur
        case blurDirection
    }

    /// 復号値を必ず範囲を丸める `init` に通します。
    /// 合成実装だと格納プロパティへ直接代入され、手で書き換えられた JSON の値がそのまま入ります。
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let `default` = ImageAdjustment.default

        self.init(
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? `default`.opacity,
            brightness: try container.decodeIfPresent(Double.self, forKey: .brightness) ?? `default`.brightness,
            padding: try container.decodeIfPresent(Double.self, forKey: .padding) ?? `default`.padding,
            blur: try container.decodeIfPresent(Double.self, forKey: .blur) ?? `default`.blur,
            blurDirection: try container.decodeIfPresent(
                ImageBlurDirection.self,
                forKey: .blurDirection
            ) ?? `default`.blurDirection
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(opacity, forKey: .opacity)
        try container.encode(brightness, forKey: .brightness)
        try container.encode(padding, forKey: .padding)
        try container.encode(blur, forKey: .blur)
        try container.encode(blurDirection, forKey: .blurDirection)
    }
}
