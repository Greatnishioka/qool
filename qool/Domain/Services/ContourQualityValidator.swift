import CoreGraphics

/// スコアリングとは別の、より厳しい合否判定。
///
/// 抽出結果を採用してよいかの最終確認に使います。不合格ならなぞり線を整形したものへ戻します。
/// [スコアリング](../../../docs/image-editing/02-contour-extractors.md#品質バリデーション)より
/// 面積比の上限と中心距離が厳しめです。
nonisolated struct ContourQualityValidator {
    static let defaultMinimumAreaRatio: CGFloat = 0.55
    static let minimumGuideOverlap: CGFloat = 0.62
    static let maximumAreaRatio: CGFloat = 1.45
    static let maximumCenterDistanceRatio: CGFloat = 0.24

    private let geometry = ContourGeometry()

    init() {}

    func isAcceptable(
        _ contour: [CGPoint],
        guide: [CGPoint],
        minimumAreaRatio: CGFloat = ContourQualityValidator.defaultMinimumAreaRatio
    ) -> Bool {
        guard contour.count >= 8, guide.count >= 3 else {
            return false
        }

        let contourBounds = geometry.bounds(for: contour)
        let guideBounds = geometry.bounds(for: guide)
        let overlap = geometry.overlapRatio(contourBounds, with: guideBounds)
        let areaRatio = geometry.polygonArea(contour) / max(0.0001, geometry.polygonArea(guide))
        let guideDiagonal = max(0.0001, hypot(guideBounds.width, guideBounds.height))
        let centerDistance = hypot(
            contourBounds.midX - guideBounds.midX,
            contourBounds.midY - guideBounds.midY
        )

        return overlap >= Self.minimumGuideOverlap
            && areaRatio >= minimumAreaRatio
            && areaRatio <= Self.maximumAreaRatio
            && centerDistance / guideDiagonal <= Self.maximumCenterDistanceRatio
    }
}
