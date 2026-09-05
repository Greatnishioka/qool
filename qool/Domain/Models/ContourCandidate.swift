import CoreGraphics

/// 抽出器が出した輪郭候補。座標は正規化（`0...1`）です。
nonisolated struct ContourCandidate {
    let contour: [CGPoint]
    let source: ContourCandidateSource
    /// ガイドに対する面積比の下限。抽出器ごとに違います。
    let minimumAreaRatio: CGFloat

    var smoothsContour: Bool {
        source.smoothsContour
    }
}
