import CoreGraphics

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
