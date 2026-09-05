import CoreGraphics

/// ビュー座標の点が輪郭の内側かを判定する。
///
/// **描画（`FillStyle(eoFill: true)`）と同じ偶奇規則で畳み込みます。**
/// 揃えないと、穴の中が見た目は透けているのにクリックを奪う、といったずれが出ます。
nonisolated struct ContourHitTest {
    private let geometry = ContourGeometry()

    init() {}

    /// - Parameters:
    ///   - contours: 正規化（`0...1`、左上原点）した輪郭。
    ///   - isTopLeftOrigin: 座標系の原点が左上か。AppKit の既定は左下なので、その場合は `false`。
    func contains(
        _ point: CGPoint,
        in contours: [CanvasPathContour],
        bounds: CGRect,
        isTopLeftOrigin: Bool
    ) -> Bool {
        guard !contours.isEmpty, bounds.contains(point), bounds.width > 0, bounds.height > 0 else {
            return false
        }

        let normalizedPoint = CGPoint(
            x: (point.x - bounds.minX) / bounds.width,
            y: (isTopLeftOrigin ? point.y - bounds.minY : bounds.maxY - point.y) / bounds.height
        )

        return contours.reduce(false) { isInside, contour in
            let polygon = contour.points.map { CGPoint(x: $0.x, y: $0.y) }

            return isInside != geometry.contains(normalizedPoint, in: polygon)
        }
    }
}
