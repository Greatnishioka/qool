import CoreGraphics
import Foundation
import iOverlay

nonisolated struct UnionCanvasElementsUseCase {
    private let polygons = CanvasElementPolygons()

    init() {}

    func callAsFunction(
        from elements: [CanvasElement],
        id: UUID = UUID(),
        styleSource: CanvasElement? = nil
    ) -> CanvasElement? {
        let unionableElements = elements.filter(isUnionable)
        guard unionableElements.count >= 2 else {
            return nil
        }

        var overlay = CGOverlay()
        var firstPath = true

        for element in unionableElements {
            let paths = polygons.filled(for: element)
            guard !paths.isEmpty else {
                continue
            }

            overlay.add(paths: paths, type: firstPath ? .subject : .clip)
            firstPath = false
        }

        guard !firstPath else {
            return nil
        }

        let shapes = overlay
            .buildGraph(fillRule: .nonZero)
            .extractShapes(overlayRule: .union)
            .filter { !$0.isEmpty }

        return makeElement(
            from: shapes,
            id: id,
            sourceElements: unionableElements,
            styleSource: styleSource
        )
    }

    private func isUnionable(_ element: CanvasElement) -> Bool {
        switch element.kind {
        case .rectangle:
            return true
        case .path:
            return element.isClosedPath && (!element.pathPoints.isEmpty || !element.pathContours.isEmpty)
        case .line, .text, .imageCutout:
            return false
        }
    }

    private func makeElement(
        from shapes: [[[CGPoint]]],
        id: UUID,
        sourceElements: [CanvasElement],
        styleSource: CanvasElement?
    ) -> CanvasElement? {
        let allPoints = shapes.flatMap { shape in shape.flatMap(\.self) }
        guard let firstPoint = allPoints.first else {
            return nil
        }

        let bounds = allPoints.dropFirst().reduce(CGRect(origin: firstPoint, size: .zero)) { partialResult, point in
            partialResult.union(CGRect(origin: point, size: .zero))
        }
        let safeFrame = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(bounds.width, 1),
            height: max(bounds.height, 1)
        )

        let contours = shapes.flatMap { shape in
            shape.map { path in
                CanvasPathContour(
                    points: path.map { normalizedPoint($0, in: safeFrame) },
                    isClosed: true
                )
            }
        }

        guard !contours.isEmpty else {
            return nil
        }

        let styleSource = styleSource ?? sourceElements.first
        return CanvasElement(
            id: id,
            kind: .path,
            frame: safeFrame,
            fillColor: styleSource?.fillColor ?? .paper,
            strokeColor: styleSource?.strokeColor ?? .ink,
            strokeWidth: styleSource?.strokeWidth ?? 2,
            showsStroke: styleSource?.showsStroke ?? true,
            pathContours: contours,
            isClosedPath: true,
            unionSourceElements: sourceElements.map(CanvasElementSnapshot.init)
        )
    }

    private func normalizedPoint(_ point: CGPoint, in frame: CGRect) -> NormalizedPoint {
        NormalizedPoint(
            x: Double((point.x - frame.minX) / frame.width),
            y: Double((point.y - frame.minY) / frame.height)
        )
    }
}
