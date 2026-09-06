import CoreGraphics
import Foundation

/// 近すぎる点を間引く。
///
/// **合成を繰り返すと頂点が増え続けます。** 手直しのたびに交点が足されるため、
/// 何度も塗ると輪郭が重くなります。`ContourSmoother` は形そのものを整えるもので、
/// ここは形を変えずに点数だけ落とすことが目的です。
nonisolated struct ContourSimplifier {
    /// 隣り合う点がこれより近ければ捨てます（正規化座標）。
    static let defaultMinimumDistance: CGFloat = 0.002

    /// これ未満には減らしません。面でなくなるためです。
    private static let minimumPointCount = 3

    init() {}

    func simplified(
        _ points: [CGPoint],
        minimumDistance: CGFloat = ContourSimplifier.defaultMinimumDistance
    ) -> [CGPoint] {
        guard points.count > Self.minimumPointCount, minimumDistance > 0 else {
            return points
        }

        var simplified: [CGPoint] = []

        for point in points {
            guard let last = simplified.last else {
                simplified.append(point)
                continue
            }

            if hypot(point.x - last.x, point.y - last.y) >= minimumDistance {
                simplified.append(point)
            }
        }

        // 閉じた輪郭なので、終点が始点に重なっていたら落とします。
        if simplified.count > Self.minimumPointCount,
           let first = simplified.first,
           let last = simplified.last,
           hypot(first.x - last.x, first.y - last.y) < minimumDistance {
            simplified.removeLast()
        }

        return simplified.count >= Self.minimumPointCount ? simplified : points
    }
}
