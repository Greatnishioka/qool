import CoreGraphics

/// マスクから輪郭を取り出す。
///
/// **切り抜きの正はマスクのままです。** 輪郭は縁の半透明を表せないので、
/// ここから出てくるのは常に「マスクから導いた写し」になります。
///
/// 輪郭を前提にしている経路が 4 つあり、そこへ渡すために要ります。
///
/// - 破線でのプレビュー表示
/// - [ContourCandidateSelector](../Services/ContourCandidateSelector.swift) の採点
/// - フローティングメモの外形（[CanvasElementPolygons](../Services/CanvasElementPolygons.swift)）
/// - なぞり直しの土台
nonisolated protocol MaskContourDeriverProtocol: Sendable {
    /// - Parameter threshold: これを超えた被覆率を内側とみなします。
    /// - Returns: 要素の枠を単位空間とした輪郭。面積の大きい順。
    func contours(from mask: CutoutMask, threshold: UInt8) -> [[CGPoint]]
}
