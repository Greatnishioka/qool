import CoreGraphics

/// 画面に並べる輪郭候補。
///
/// `source` が `nil` のものは**なぞり線をそのまま整えた「手描き」**で、
/// 抽出器の結果ではないため常に末尾に置かれ、スコアも持ちません。
/// 抽出器が何も出さなかったときの受け皿になります。
nonisolated struct CutoutCandidate: Identifiable {
    let source: ContourCandidateSource?
    let contours: [CanvasPathContour]
    let score: CGFloat?
    /// 自動で選ばれた候補。スコアが基準を超えた中の最高得点です。
    let isRecommended: Bool

    var id: String { source?.id ?? "handDrawn" }

    var displayName: String { source?.displayName ?? "手描き" }

    var helpText: String { source?.helpText ?? "なぞった線をそのまま整えた候補です" }
}
