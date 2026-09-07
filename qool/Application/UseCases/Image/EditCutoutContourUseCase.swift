import CoreGraphics
import Foundation
import iOverlay

/// 切り抜きの輪郭に、なぞった領域を足す / 引く。
nonisolated struct EditCutoutContourUseCase {
    /// 面にならない多角形は捨てます。
    private static let minimumPointCount = 3

    /// これより小さい形は捨てます（正規化座標での面積）。
    ///
    /// **消しゴムは極小の欠片を残します。** 実測で 500 手のあと輪郭が 46 本まで増えました。
    /// 0.003 四方は 320pt 表示で 1pt 弱なので、見えないものが履歴と描画を重くしているだけです。
    ///
    /// **`iOverlay` の `minArea` は使いません。** 内部の整数座標に換算されるため、
    /// 正規化座標（0〜1）で渡すと桁が合わず、まともな形まで消えました。自分で測ります。
    private static let minimumShapeArea: CGFloat = 0.00001

    private let simplifier = ContourSimplifier()
    private let geometry = ContourGeometry()

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
            .filter { geometry.polygonArea($0) >= Self.minimumShapeArea }
            .map { path in
                CanvasPathContour(
                    points: path.map { NormalizedPoint(x: Double($0.x), y: Double($0.y)) },
                    isClosed: true
                )
            }
    }
}
