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
        guard let shapes = unionShapes(of: canvas, includingAdjustment: true) else {
            return nil
        }

        // 紙を敷く形は余白とぼかしを含めません。含めるとぼけた縁が塗り潰されます。
        let paperShapes = unionShapes(of: canvas, includingAdjustment: false) ?? shapes

        return makeOutline(from: shapes, paperShapes: paperShapes)
    }

    /// 全要素を合成した形。1 つも面を持たなければ `nil`。
    private func unionShapes(of canvas: Canvas, includingAdjustment: Bool) -> [[[CGPoint]]]? {
        var overlay = CGOverlay()
        var hasSubject = false

        for element in canvas.elements {
            let paths = polygons
                .outline(for: element, includingAdjustment: includingAdjustment)
                .filter { $0.count >= Self.minimumContourPoints }
            guard !paths.isEmpty else {
                continue
            }

            overlay.add(paths: paths, type: hasSubject ? .clip : .subject)
            hasSubject = true
        }

        guard hasSubject else {
            return nil
        }

        return overlay
            .buildGraph(fillRule: .nonZero)
            .extractShapes(overlayRule: .union)
            .filter { !$0.isEmpty }
    }

    private func makeOutline(
        from shapes: [[[CGPoint]]],
        paperShapes: [[[CGPoint]]]
    ) -> FloatingMemoOutline? {
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

        let contours = normalizedContours(of: shapes, in: safeBounds)

        guard !contours.isEmpty else {
            return nil
        }

        let paperContours = normalizedContours(of: paperShapes, in: safeBounds)

        return FloatingMemoOutline(
            bounds: safeBounds,
            contours: contours,
            // 紙の形が作れなければ輪郭で代用します。硬い縁になりますが、
            // 紙が無くて背面が透けるよりはましです。
            paperContours: paperContours.isEmpty ? contours : paperContours
        )
    }

    /// `bounds` を単位空間として正規化した輪郭。面にならない断片は捨てます。
    private func normalizedContours(
        of shapes: [[[CGPoint]]],
        in bounds: CGRect
    ) -> [CanvasPathContour] {
        shapes
            .flatMap { shape in shape }
            .filter { $0.count >= Self.minimumContourPoints }
            .map { path in
                CanvasPathContour(
                    points: path.map { normalizedPoint($0, in: bounds) },
                    isClosed: true
                )
            }
    }

    private func normalizedPoint(_ point: CGPoint, in bounds: CGRect) -> NormalizedPoint {
        NormalizedPoint(
            x: Double((point.x - bounds.minX) / bounds.width),
            y: Double((point.y - bounds.minY) / bounds.height)
        )
    }
}
