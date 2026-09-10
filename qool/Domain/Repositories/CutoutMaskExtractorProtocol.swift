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
