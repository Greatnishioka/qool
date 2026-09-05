import CoreGraphics

/// 輪郭の幾何計算。
///
/// **移植元では bounds / 面積 / 内外判定が 4 つのファイルに複製されていました。**
/// 同じ実装なので 1 箇所にまとめています。座標は正規化（`0...1`）です。
nonisolated struct ContourGeometry {
    init() {}

    /// 点列を囲む矩形。幅・高さは 0 になりません（0 除算を避けるため）。
    func bounds(for points: [CGPoint]) -> CGRect {
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

    func polygonArea(_ points: [CGPoint]) -> CGFloat {
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

    /// `rect` のうち `otherRect` と重なっている割合。
    func overlapRatio(_ rect: CGRect, with otherRect: CGRect) -> CGFloat {
        let intersection = rect.intersection(otherRect)
        guard !intersection.isNull, rect.width > 0, rect.height > 0 else {
            return 0
        }

        return intersection.width * intersection.height / (rect.width * rect.height)
    }

    func insideRatio(_ points: [CGPoint], guide: [CGPoint]) -> CGFloat {
        guard !points.isEmpty else {
            return 0
        }

        return CGFloat(points.count { contains($0, in: guide) }) / CGFloat(points.count)
    }

    /// 交差数判定（ray casting）。
    func contains(_ point: CGPoint, in polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }

        var isInside = false
        var previousIndex = polygon.count - 1

        for currentIndex in polygon.indices {
            let current = polygon[currentIndex]
            let previous = polygon[previousIndex]
            let intersects = (current.y > point.y) != (previous.y > point.y)
                && point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x

            if intersects {
                isInside.toggle()
            }

            previousIndex = currentIndex
        }

        return isInside
    }
}
