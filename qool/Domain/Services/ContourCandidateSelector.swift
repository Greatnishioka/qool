import CoreGraphics

/// 輪郭候補をスコアリングし、推奨を1つ選ぶ。
///
/// StarWindow からの移植（[スコアリング](../../../docs/image-editing/02-contour-extractors.md#スコアリング)）。
/// **まず足切りを全部通らないと候補になりません**（`nil`）。
/// 通ったものに重み付き和と `source.bias` を足し、背景差分だけ補正を引きます。
nonisolated struct ContourCandidateSelector {
    /// 自動で推奨に上げる最低スコア。これを超える候補がなければ推奨は「手描き」になります。
    static let minimumAutoScore: CGFloat = 2.05
    /// ガイドとの bounds 重なり率の下限。
    static let minimumGuideOverlap: CGFloat = 0.62
    /// ガイド内部に入っている点の割合の下限。
    static let minimumInsideRatio: CGFloat = 0.58
    /// 面積比の上限。ガイドより大きすぎる候補は弾きます。
    static let maximumAreaRatio: CGFloat = 1.48
    /// 中心距離 ÷ ガイド対角長の上限。
    static let maximumCenterDistanceRatio: CGFloat = 0.28

    private let geometry = ContourGeometry()

    init() {}

    /// 自動で推奨に上げる候補。**移植元でも呼び出し元はありません**が、
    /// 判定の基準そのものなので契約として残しています。
    func bestCandidate(from candidates: [ContourCandidate], guide: [CGPoint]) -> ContourCandidate? {
        scoredCandidates(from: candidates, guide: guide)
            .filter { $0.score >= Self.minimumAutoScore }
            .max { first, second in first.score < second.score }?
            .candidate
    }

    /// 足切りを通った候補だけを、スコア付きで返す。
    func scoredCandidates(
        from candidates: [ContourCandidate],
        guide: [CGPoint]
    ) -> [(candidate: ContourCandidate, score: CGFloat)] {
        candidates.compactMap { candidate in
            guard let score = score(candidate, guide: guide) else {
                return nil
            }

            return (candidate, score)
        }
    }

    private func score(_ candidate: ContourCandidate, guide: [CGPoint]) -> CGFloat? {
        guard candidate.contour.count >= 8, guide.count >= 3 else {
            return nil
        }

        let contourBounds = geometry.bounds(for: candidate.contour)
        let guideBounds = geometry.bounds(for: guide)
        let guideArea = max(0.0001, geometry.polygonArea(guide))
        let contourArea = geometry.polygonArea(candidate.contour)
        let areaRatio = contourArea / guideArea
        let guideDiagonal = max(0.0001, hypot(guideBounds.width, guideBounds.height))
        let centerDistance = hypot(
            contourBounds.midX - guideBounds.midX,
            contourBounds.midY - guideBounds.midY
        ) / guideDiagonal
        let overlap = geometry.overlapRatio(contourBounds, with: guideBounds)
        let inside = geometry.insideRatio(candidate.contour, guide: guide)

        guard
            overlap >= Self.minimumGuideOverlap,
            inside >= Self.minimumInsideRatio,
            areaRatio >= candidate.minimumAreaRatio,
            areaRatio <= Self.maximumAreaRatio,
            centerDistance <= Self.maximumCenterDistanceRatio
        else {
            return nil
        }

        let centerScore = max(0, 1 - centerDistance / Self.maximumCenterDistanceRatio)

        return overlap * 0.95
            + inside * 0.75
            + centerScore * 0.55
            + areaFitScore(areaRatio) * 0.55
            + candidate.source.bias
            - compactnessPenalty(for: candidate, contourArea: contourArea, contourBounds: contourBounds)
    }

    /// 面積比 0.35〜1.0 が満点。外れるほど減点します。
    private func areaFitScore(_ areaRatio: CGFloat) -> CGFloat {
        if areaRatio < 0.35 {
            return max(0, areaRatio / 0.35)
        }

        if areaRatio > 1 {
            return max(0, 1 - (areaRatio - 1) / 0.48)
        }

        return 1
    }

    /// 背景差分が bounds をほぼ埋めている場合の補正。
    /// 「画像全体を拾ってしまった」ケースを弾くためのものです。
    private func compactnessPenalty(
        for candidate: ContourCandidate,
        contourArea: CGFloat,
        contourBounds: CGRect
    ) -> CGFloat {
        guard candidate.source == .backgroundDifference else {
            return 0
        }

        let boundsArea = max(0.0001, contourBounds.width * contourBounds.height)

        return contourArea / boundsArea > 0.78 ? 0.18 : 0
    }
}
