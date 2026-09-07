import SwiftUI

/// 正規化された輪郭を、与えられた矩形に合わせて折れ線で描く。
///
/// **複数の輪郭を 1 つの `Path` に入れるのが要点です。** 穴あき形状は
/// `FillStyle(eoFill: true)` と組み合わせて表現します。
struct MultiContourPathShape: Shape {
    let contours: [CanvasPathContour]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        for contour in contours where !contour.points.isEmpty {
            let cgPoints = contour.points.map { point in
                CGPoint(
                    x: rect.minX + rect.width * CGFloat(point.x),
                    y: rect.minY + rect.height * CGFloat(point.y)
                )
            }

            guard let firstPoint = cgPoints.first else {
                continue
            }

            path.move(to: firstPoint)
            for point in cgPoints.dropFirst() {
                path.addLine(to: point)
            }
            if contour.isClosed {
                path.closeSubpath()
            }
        }

        return path
    }
}
