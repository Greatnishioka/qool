import CoreGraphics

/// 画像から切り抜きのマスクを取り出す。
///
/// **Domain は Vision も OpenCV も知りません。** 実装は Infrastructure に置き、
/// ここでは「画像となぞりを渡すとマスクが返る」という契約だけを持ちます。
///
/// **輪郭ではなくマスクを返します。** 縁の半透明を残せるのはマスクだけで、
/// 輪郭にした時点でその情報は失われます
/// （[設計](https://github.com/Greatnishioka/qool/issues/12)）。
nonisolated protocol CutoutMaskExtractorProtocol: Sendable {
    /// - Parameters:
    ///   - image: 元画像。
    ///   - guide: なぞり線。正規化座標（`0...1`）で、左上原点です。
    /// - Returns: 画像の枠を単位空間としたマスク。見つからなければ `nil`。
    func extractMask(in image: CGImage, guidedBy guide: [CGPoint]) async -> CutoutMask?
}

/// マスクから輪郭を取り出す。
///
/// **プレビューと採点にだけ使います。** 破線の表示と
/// [ContourCandidateSelector](../Services/ContourCandidateSelector.swift) の採点は
/// 輪郭を前提にしているので、マスクから導出して渡します。切り抜きの正はマスクのままです。
nonisolated protocol MaskContourDeriverProtocol: Sendable {
    /// - Parameter threshold: これを超えた被覆率を内側とみなします。
    /// - Returns: 要素の枠を単位空間とした輪郭。面積の大きい順。
    func contours(from mask: CutoutMask, threshold: UInt8) -> [[CGPoint]]
}
