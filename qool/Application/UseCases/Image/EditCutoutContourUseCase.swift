import CoreGraphics
import Foundation
import iOverlay

/// 切り抜きの輪郭に、なぞった領域を足す / 引く。
nonisolated struct EditCutoutContourUseCase {
    /// 面にならない多角形は捨てます。
    private static let minimumPointCount = 3

    private let simplifier = ContourSimplifier()

    init() {}

    /// - Parameters:
    ///   - contours: 今の輪郭（正規化座標）。
    ///   - polygons: なぞりから作った領域。ブラシなら `BrushStrokeOutline`、投げ縄なら囲んだ形そのもの。
    /// - Returns: 合成後の輪郭。変えられなければ元のまま返します。
    func callAsFunction(
        _ contours: [CanvasPathContour],
        combining polygons: [[CGPoint]],
        mode: ContourEditMode
    ) -> [CanvasPathContour] {
        let brush = polygons.filter { $0.count >= Self.minimumPointCount }
        guard !brush.isEmpty else {
            return contours
        }

        let existing = contours
            .filter(\.isClosed)
            .map { contour in contour.points.map { CGPoint(x: $0.x, y: $0.y) } }
            .filter { $0.count >= Self.minimumPointCount }

        guard !existing.isEmpty else {
            // 輪郭がまだない状態。引くものがないので、足すときだけなぞりがそのまま輪郭になります。
            return mode == .add ? combine(subject: brush, clip: [], rule: .union) : contours
        }

        return combine(
            subject: existing,
            clip: brush,
            rule: mode == .add ? .union : .difference
        )
    }

    private func combine(
        subject: [[CGPoint]],
        clip: [[CGPoint]],
        rule: OverlayRule
    ) -> [CanvasPathContour] {
        var overlay = CGOverlay()
        overlay.add(paths: subject, type: .subject)

        if !clip.isEmpty {
            overlay.add(paths: clip, type: .clip)
        }

        let shapes = overlay
            .buildGraph(fillRule: .nonZero)
            .extractShapes(overlayRule: rule)

        return shapes
            .flatMap { shape in shape }
            .map { path in simplifier.simplified(path) }
            .filter { $0.count >= Self.minimumPointCount }
            .map { path in
                CanvasPathContour(
                    points: path.map { NormalizedPoint(x: Double($0.x), y: Double($0.y)) },
                    isClosed: true
                )
            }
    }
}
