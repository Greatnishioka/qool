import CoreGraphics

/// 押した場所から、色の近い範囲を広げてマスクにする。
///
/// **取っ手の内側のような「囲まれた領域」を一度に選ぶための道具です。**
/// ブラシでなぞるより速く、境界も色の変わり目に沿います。
nonisolated protocol RegionMaskExtractorProtocol: Sendable {
    /// - Parameters:
    ///   - image: 元画像。
    ///   - point: 押した場所。正規化座標（`0...1`）で、左上原点です。
    ///   - tolerance: 色の違いをどこまで同じ領域とみなすか（`0...255`）。
    /// - Returns: 画像の枠を単位空間としたマスク。広がらなければ `nil`。
    ///
    /// **非同期です。** 原寸の画像を読み込んでから縮めるので、
    /// クリックの処理から同期で呼ぶとメインスレッドが塞がります。
    func regionMask(in image: CGImage, at point: CGPoint, tolerance: Int) async -> CutoutMask?
}
