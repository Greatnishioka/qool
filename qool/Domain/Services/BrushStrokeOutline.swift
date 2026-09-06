import CoreGraphics
import Foundation

/// ブラシのなぞりを多角形へ変換する。
///
/// **1 本の多角形にまとめません。** 線分ごとのカプセル（長方形 + 両端の半円）に割ります。
/// 自己交差する軌跡を 1 本の輪郭へ落とそうとすると縁が破綻しますが、
/// 凸なカプセルの集まりなら、重なりは合成側（`fillRule: .nonZero`）が解決します。
nonisolated struct BrushStrokeOutline {
    /// 半円を折れ線で近似する分割数。
    private static let capSegments = 8
    /// 円（点を1つだけ打ったとき）の分割数。
    private static let circleSegments = 16
    /// これより短い線分は「同じ点」として円に落とします。0 除算を避けるためです。
    private static let minimumSegmentLength: CGFloat = 1e-9

    init() {}

    /// - Parameters:
    ///   - stroke: なぞった点列。座標系は問いませんが、`radius` と揃っている必要があります。
    ///   - radius: ブラシの半径。
    func polygons(for stroke: [CGPoint], radius: CGFloat) -> [[CGPoint]] {
        guard radius > 0, let first = stroke.first else {
            return []
        }

        guard stroke.count >= 2 else {
            return [circle(at: first, radius: radius)]
        }

        return (0..<(stroke.count - 1)).map { index in
            capsule(from: stroke[index], to: stroke[index + 1], radius: radius)
                ?? circle(at: stroke[index], radius: radius)
        }
    }

    private func capsule(from start: CGPoint, to end: CGPoint, radius: CGFloat) -> [CGPoint]? {
        let angle = atan2(end.y - start.y, end.x - start.x)

        guard hypot(end.x - start.x, end.y - start.y) > Self.minimumSegmentLength else {
            return nil
        }

        var points: [CGPoint] = []
        points.reserveCapacity((Self.capSegments + 1) * 2)

        appendArc(to: &points, center: end, radius: radius, from: angle - .pi / 2, to: angle + .pi / 2)
        appendArc(to: &points, center: start, radius: radius, from: angle + .pi / 2, to: angle + .pi * 1.5)

        return points
    }

    private func circle(at center: CGPoint, radius: CGFloat) -> [CGPoint] {
        (0..<Self.circleSegments).map { index in
            let angle = CGFloat(index) / CGFloat(Self.circleSegments) * .pi * 2

            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }

    private func appendArc(
        to points: inout [CGPoint],
        center: CGPoint,
        radius: CGFloat,
        from startAngle: CGFloat,
        to endAngle: CGFloat
    ) {
        for step in 0...Self.capSegments {
            let progress = CGFloat(step) / CGFloat(Self.capSegments)
            let angle = startAngle + (endAngle - startAngle) * progress
            points.append(CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
        }
    }
}
