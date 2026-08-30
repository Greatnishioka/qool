/// 切り抜き画像の見た目を決める値。
///
/// 範囲と既定値は StarWindow の `MemoPreviewConfiguration` に合わせています
/// （[モデル拡張](../../../docs/image-editing/04-integration-plan.md#調整パラメータ)）。
/// 移植前の qool の値は範囲が狭く、上位互換である StarWindow 側を採用する判断です。
///
/// 範囲外の値は `init` が丸めます。手で書き換えられた JSON から
/// 負のぼかし半径のような描画できない値が入るのを防ぐためです。
nonisolated struct ImageAdjustment: Equatable, Hashable, Codable {
    static let opacityRange: ClosedRange<Double> = 0.2...1
    static let brightnessRange: ClosedRange<Double> = -0.15...0.45
    static let paddingRange: ClosedRange<Double> = 0...80
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
        opacity: Double = 0.2,
        brightness: Double = 0.1,
        padding: Double = 60,
        blur: Double = 0,
        blurDirection: ImageBlurDirection = .outward
    ) {
        self.opacity = Self.clamped(opacity, to: Self.opacityRange)
        self.brightness = Self.clamped(brightness, to: Self.brightnessRange)
        self.padding = Self.clamped(padding, to: Self.paddingRange)
        self.blur = Self.clamped(blur, to: Self.blurRange)
        self.blurDirection = blurDirection
    }

    /// 非有限値は範囲の下限として扱う。`.nan` を素通しさせると `Equatable` の反射律が壊れます。
    private static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else {
            return range.lowerBound
        }

        return min(max(value, range.lowerBound), range.upperBound)
    }
}
