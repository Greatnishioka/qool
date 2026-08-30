import CoreGraphics

/// ガイド（ユーザーのなぞり）が矩形らしければ、輪郭を矩形に整える。
///
/// StarWindow からの移植（[取り込み計画](../../../docs/image-editing/04-integration-plan.md)）。
/// 座標は正規化（`0...1`）で扱います。
nonisolated struct RectangularGuideContour {
    /// 矩形として扱うかどうかの切り替え。StarWindow でのチューニング用スイッチです。
    static let isEnabled = true
    /// 1 辺あたりの点数。`isRectangleLikeContour` の判定にも使うため、辺の分割数と揃えます。
    static let pointsPerSide = 18
    /// bounds をどれだけ埋めていれば矩形とみなすか。
    static let minimumFillRatio: CGFloat = 0.78
    /// 各辺がどれだけの割合をなぞられていれば矩形とみなすか。
    static let minimumSideCoverage: CGFloat = 0.58

    init() {}

    func detectContour(from guide: [CGPoint]) -> [CGPoint]? {
        guard Self.isEnabled, isRectangleLikeGuide(guide) else {
            return nil
        }

        return rectangularContour(for: bounds(for: guide))
    }

    func isRectangleLikeContour(_ points: [CGPoint]) -> Bool {
        guard points.count >= 8 else {
            return false
        }

        let pointCount = Self.pointsPerSide
        guard points.count >= pointCount * 4 - 4 else {
            return false
        }

        let bounds = bounds(for: points)
        guard bounds.width > 0.01, bounds.height > 0.01 else {
            return false
        }

        let tolerance = max(0.003, min(bounds.width, bounds.height) * 0.025)
        let nearSides = points.filter { point in
            abs(point.x - bounds.minX) <= tolerance
                || abs(point.x - bounds.maxX) <= tolerance
                || abs(point.y - bounds.minY) <= tolerance
                || abs(point.y - bounds.maxY) <= tolerance
        }

        return CGFloat(nearSides.count) / CGFloat(points.count) > 0.9
    }

    func rectangularContour(for rect: CGRect) -> [CGPoint] {
        let rect = rect.clampedToUnit()
        let segments = max(2, Self.pointsPerSide)
        var points: [CGPoint] = []

        appendLine(
            from: CGPoint(x: rect.minX, y: rect.minY),
            to: CGPoint(x: rect.maxX, y: rect.minY),
            segments: segments,
            to: &points
        )
        appendLine(
            from: CGPoint(x: rect.maxX, y: rect.minY),
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            segments: segments,
            to: &points
        )
        appendLine(
            from: CGPoint(x: rect.maxX, y: rect.maxY),
            to: CGPoint(x: rect.minX, y: rect.maxY),
            segments: segments,
            to: &points
        )
        appendLine(
            from: CGPoint(x: rect.minX, y: rect.maxY),
            to: CGPoint(x: rect.minX, y: rect.minY),
            segments: segments,
            to: &points
        )

        return points
    }

    /// 点数が少ないガイド（12 点以下）は、面積比だけで判定します。
    /// 辺のなぞり具合を見るには点が足りないためです。
    func isRectangleLikeGuide(_ guide: [CGPoint]) -> Bool {
        guard guide.count >= 4 else {
            return false
        }

        let guideBounds = bounds(for: guide)
        guard guideBounds.width > 0.04, guideBounds.height > 0.04 else {
            return false
        }

        let boundsArea = guideBounds.width * guideBounds.height
        let fillRatio = polygonArea(guide) / max(0.0001, boundsArea)
        guard fillRatio >= Self.minimumFillRatio else {
            return false
        }

        if guide.count <= 12 {
            return true
        }

        let tolerance = max(0.012, min(guideBounds.width, guideBounds.height) * 0.09)
        let topCoverage = sideCoverage(
            guide.filter { abs($0.y - guideBounds.minY) <= tolerance }.map(\.x),
            span: guideBounds.width
        )
        let bottomCoverage = sideCoverage(
            guide.filter { abs($0.y - guideBounds.maxY) <= tolerance }.map(\.x),
            span: guideBounds.width
        )
        let leftCoverage = sideCoverage(
            guide.filter { abs($0.x - guideBounds.minX) <= tolerance }.map(\.y),
            span: guideBounds.height
        )
        let rightCoverage = sideCoverage(
            guide.filter { abs($0.x - guideBounds.maxX) <= tolerance }.map(\.y),
            span: guideBounds.height
        )
        let minimumCoverage = Self.minimumSideCoverage

        return topCoverage >= minimumCoverage
            && bottomCoverage >= minimumCoverage
            && leftCoverage >= minimumCoverage
            && rightCoverage >= minimumCoverage
    }

    private func appendLine(
        from start: CGPoint,
        to end: CGPoint,
        segments: Int,
        to points: inout [CGPoint]
    ) {
        for index in 0..<segments {
            let t = CGFloat(index) / CGFloat(segments)
            points.append(
                CGPoint(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t
                )
            )
        }
    }

    private func sideCoverage(_ values: [CGFloat], span: CGFloat) -> CGFloat {
        guard let minValue = values.min(), let maxValue = values.max(), span > 0 else {
            return 0
        }

        return (maxValue - minValue) / span
    }

    private func bounds(for points: [CGPoint]) -> CGRect {
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 1
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 1

        return CGRect(
            x: minX,
            y: minY,
            width: max(0.0001, maxX - minX),
            height: max(0.0001, maxY - minY)
        )
    }

    private func polygonArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else {
            return 0
        }

        var area: CGFloat = 0

        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            area += current.x * next.y - next.x * current.y
        }

        return abs(area / 2)
    }
}
