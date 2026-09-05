import CoreGraphics

/// 画像から被写体の輪郭を取り出す。
///
/// **Domain は Vision を知りません。** 実装は Infrastructure に置き、
/// ここでは「画像となぞりを渡すと正規化された輪郭が返る」という契約だけを持ちます。
///
/// `CGImage` を受けるのは、Domain が既に `CoreGraphics` に依存しているためです。
/// `NSImage` は AppKit の型なので、変換は呼び出し側（Presentation）が行います。
nonisolated protocol SubjectContourExtractorProtocol: Sendable {
    /// - Parameters:
    ///   - image: 元画像。
    ///   - guide: なぞり線。正規化座標（`0...1`）で、左上原点です。
    /// - Returns: 正規化された輪郭。見つからなければ `nil`。
    func extractContour(in image: CGImage, guidedBy guide: [CGPoint]) async -> [CGPoint]?
}
