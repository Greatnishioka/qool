import CoreGraphics

/// 輪郭を外側へ膨らませる。負の値を渡せば収縮になります。
///
/// StarWindow からの移植（[取り込み計画](../../../docs/image-editing/04-integration-plan.md)）。
/// 入出力とも正規化座標（`0...1`）で、膨らませる量だけがピクセル単位です。
nonisolated struct ContourPadding {
    private let rectangularGuideContour: RectangularGuideContour

    init(rectangularGuideContour: RectangularGuideContour = RectangularGuideContour()) {
        self.rectangularGuideContour = rectangularGuideContour
    }

    /// 矩形らしい輪郭は bounds を広げて作り直します。
    /// 重心から押し出すと、角だけが外へ飛び出して形が崩れるためです。
    func expanded(
        _ points: [CGPoint],
        imageSize: CGSize,
        paddingPixels: CGFloat
    ) -> [CGPoint] {
        guard points.count >= 3, paddingPixels != 0, imageSize.width > 0, imageSize.height > 0 else {
            return points
        }

        if rectangularGuideContour.isRectangleLikeContour(points) {
            let normalizedDX = paddingPixels / imageSize.width
            let normalizedDY = paddingPixels / imageSize.height
            return rectangularGuideContour.rectangularContour(
                for: normalizedBounds(for: points).insetBy(dx: -normalizedDX, dy: -normalizedDY).clampedToUnit()
            )
        }

        let pixelPoints = points.map { point in
            CGPoint(x: point.x * imageSize.width, y: point.y * imageSize.height)
        }
        let center = centroid(of: pixelPoints)

        return pixelPoints.map { point in
            let vector = CGPoint(x: point.x - center.x, y: point.y - center.y)
            let length = max(0.001, hypot(vector.x, vector.y))
            let expandedPoint = CGPoint(
                x: point.x + vector.x / length * paddingPixels,
                y: point.y + vector.y / length * paddingPixels
            )

            return CGPoint(
                x: expandedPoint.x / imageSize.width,
                y: expandedPoint.y / imageSize.height
            )
        }
    }

    private func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else {
            return .zero
        }

        let sum = points.reduce(CGPoint.zero) { partialResult, point in
            CGPoint(x: partialResult.x + point.x, y: partialResult.y + point.y)
        }

        return CGPoint(
            x: sum.x / CGFloat(points.count),
            y: sum.y / CGFloat(points.count)
        )
    }

    private func normalizedBounds(for points: [CGPoint]) -> CGRect {
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
}
