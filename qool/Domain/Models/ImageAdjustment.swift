/// 切り抜き画像の見た目を決める値。
///
/// 範囲は StarWindow の `MemoPreviewConfiguration` に合わせています
/// （[モデル拡張](../../../docs/image-editing/04-integration-plan.md#調整パラメータ)）。
///
/// **既定値だけは StarWindow と変えて「何もしない」にしています。**
/// StarWindow は画像を紙の背景として敷いていたため薄く広い余白が既定でしたが、
/// qool の画像はキャンバス上の要素です。取り込んだ直後に薄くなるのは意図と違います。
///
/// 範囲外の値は `init` が丸めます。手で書き換えられた JSON から
/// 負のぼかし半径のような描画できない値が入るのを防ぐためです。
nonisolated struct ImageAdjustment: Equatable, Hashable, Codable {
    static let opacityRange: ClosedRange<Double> = 0.2...1
    static let brightnessRange: ClosedRange<Double> = -0.15...0.45
    /// **StarWindow の 0...80 から狭めています。** 余白の分だけ元画像を残す必要があり、
    /// 80pt を保証すると大きな写真がほとんど切り詰められなくなるためです
    /// （[CutoutCropGeometry](../Services/CutoutCropGeometry.swift)）。
    static let paddingRange: ClosedRange<Double> = 0...24
    static let blurRange: ClosedRange<Double> = 0...14

    static let `default` = ImageAdjustment()

    let opacity: Double
    let brightness: Double
    /// 輪郭の外側へ広げる余白（px）。
    let padding: Double
    /// ぼかし半径（px）。
    let blur: Double
    let blurDirection: ImageBlurDirection

    init(
        opacity: Double = 1,
        brightness: Double = 0,
        padding: Double = 0,
        blur: Double = 0,
        blurDirection: ImageBlurDirection = .outward
    ) {
        self.opacity = Self.clamped(opacity, to: Self.opacityRange)
        self.brightness = Self.clamped(brightness, to: Self.brightnessRange)
        self.padding = Self.clamped(padding, to: Self.paddingRange)
        self.blur = Self.clamped(blur, to: Self.blurRange)
        self.blurDirection = blurDirection
    }

    /// 一部だけ差し替えた値を返す。
    ///
    /// **`init` を通すので丸めが効きます。** 格納プロパティを `var` にして直接書き換えると、
    /// 範囲外の値がそのまま入り、描画できない状態を作れてしまいます。
    func updated(
        opacity: Double? = nil,
        brightness: Double? = nil,
        padding: Double? = nil,
        blur: Double? = nil,
        blurDirection: ImageBlurDirection? = nil
    ) -> ImageAdjustment {
        ImageAdjustment(
            opacity: opacity ?? self.opacity,
            brightness: brightness ?? self.brightness,
            padding: padding ?? self.padding,
            blur: blur ?? self.blur,
            blurDirection: blurDirection ?? self.blurDirection
        )
    }

    /// 非有限値は範囲の下限として扱う。`.nan` を素通しさせると `Equatable` の反射律が壊れます。
    private static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else {
            return range.lowerBound
        }

        return min(max(value, range.lowerBound), range.upperBound)
    }
}
