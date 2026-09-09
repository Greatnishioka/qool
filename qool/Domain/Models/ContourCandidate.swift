import CoreGraphics

/// 抽出器が出した輪郭候補。座標は正規化（`0...1`）です。
nonisolated struct ContourCandidate {
    let contour: [CGPoint]
    /// 抽出器が返したマスク。**これが切り抜きの正で、`contour` は表示と採点のための写しです。**
    /// 幾何ベースの抽出器（矩形補正）は持ちません。
    var mask: CutoutMask?
    let source: ContourCandidateSource
    /// ガイドに対する面積比の下限。抽出器ごとに違います。
    let minimumAreaRatio: CGFloat

    var smoothsContour: Bool {
        source.smoothsContour
    }
}
