import CoreGraphics
import Foundation
import iOverlay

/// キャンバス全体の外形を求める。
///
/// **移植元は画像 1 枚の輪郭をそのままウィンドウの形にしていましたが、qool のウィンドウは
/// キャンバス（図形 + 複数の切り抜き）1 枚分です。** 要素をすべて合成した形を使います。
nonisolated struct BuildFloatingMemoOutlineUseCase {
    /// 合成後にこれ未満の点しか残らない輪郭は捨てます。面にならず、ヒットテストも通りません。
    private static let minimumContourPoints = 3

    private let polygons = CanvasElementPolygons()

    init() {}

    func callAsFunction(from canvas: Canvas) -> FloatingMemoOutline? {
        var overlay = CGOverlay()
        var hasSubject = false

        for element in canvas.elements {
            let paths = polygons.outline(for: element).filter { $0.count >= Self.minimumContourPoints }
            guard !paths.isEmpty else {
                continue
            }

            overlay.add(paths: paths, type: hasSubject ? .clip : .subject)
            hasSubject = true
        }

        guard hasSubject else {
            return nil
        }

        let shapes = overlay
            .buildGraph(fillRule: .nonZero)
            .extractShapes(overlayRule: .union)
            .filter { !$0.isEmpty }

        return makeOutline(from: shapes)
    }

    private func makeOutline(from shapes: [[[CGPoint]]]) -> FloatingMemoOutline? {
        let allPoints = shapes.flatMap { $0.flatMap { $0 } }

        // firstPointは左上の原点
        guard let firstPoint = allPoints.first else {
            return nil
        }

        // bounding boxを求める。すべての点を含む最小の矩形。
        let bounds = allPoints.dropFirst().reduce(CGRect(origin: firstPoint, size: .zero)) { partialResult, point in
            partialResult.union(CGRect(origin: point, size: .zero))
        }
        
        // 1 点だけ、あるいは水平・垂直に潰れた形でも 0 除算しないようにします。
        let safeBounds = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(bounds.width, 1),
            height: max(bounds.height, 1)
        )

        let contours = shapes
            .flatMap { shape in shape }
            .filter { $0.count >= Self.minimumContourPoints }
            .map { path in
                CanvasPathContour(
                    points: path.map { normalizedPoint($0, in: safeBounds) },
                    isClosed: true
                )
            }

        guard !contours.isEmpty else {
            return nil
        }

        return FloatingMemoOutline(bounds: safeBounds, contours: contours)
    }

    private func normalizedPoint(_ point: CGPoint, in bounds: CGRect) -> NormalizedPoint {
        NormalizedPoint(
            x: Double((point.x - bounds.minX) / bounds.width),
            y: Double((point.y - bounds.minY) / bounds.height)
        )
    }
}
