import CoreGraphics
import Foundation
import iOverlay

struct CanvasUnionUseCase {
    nonisolated init() {}

    func unionElement(
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
            let paths = polygonPaths(for: element)
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

    private func polygonPaths(for element: CanvasElement) -> [[CGPoint]] {
        switch element.kind {
        case .rectangle:
            return [[
                CGPoint(x: element.frame.minX, y: element.frame.minY),
                CGPoint(x: element.frame.maxX, y: element.frame.minY),
                CGPoint(x: element.frame.maxX, y: element.frame.maxY),
                CGPoint(x: element.frame.minX, y: element.frame.maxY)
            ]]
        case .path:
            if !element.pathContours.isEmpty {
                return element.pathContours
                    .filter(\.isClosed)
                    .map { contour in
                        contour.points.map { absolutePoint($0, in: element.frame) }
                    }
                    .filter { $0.count >= 3 }
            }

            return [sampledPathPoints(for: element)]
                .filter { $0.count >= 3 }
        case .line, .text, .imageCutout:
            return []
        }
    }

    private func sampledPathPoints(for element: CanvasElement) -> [CGPoint] {
        let points = element.pathPoints.map { absolutePoint($0, in: element.frame) }
        guard let firstPoint = points.first else {
            return []
        }

        guard points.count > 2 else {
            return points
        }

        var sampledPoints: [CGPoint] = [firstPoint]
        var currentPoint = firstPoint

        for index in 1..<points.count {
            let endPoint: CGPoint
            let controlPoint: CGPoint

            if index == points.count - 1 {
                endPoint = points[index]
                controlPoint = points[index - 1]
            } else {
                endPoint = CGPoint(
                    x: (points[index].x + points[index + 1].x) / 2,
                    y: (points[index].y + points[index + 1].y) / 2
                )
                controlPoint = points[index]
            }

            sampledPoints.append(contentsOf: sampleQuadCurve(
                from: currentPoint,
                control: controlPoint,
                to: endPoint
            ))
            currentPoint = endPoint
        }

        guard element.isClosedPath else {
            return sampledPoints
        }

        let lastPoint = points[points.count - 1]
        let closingMidpoint = CGPoint(
            x: (lastPoint.x + firstPoint.x) / 2,
            y: (lastPoint.y + firstPoint.y) / 2
        )

        sampledPoints.append(contentsOf: sampleQuadCurve(
            from: currentPoint,
            control: lastPoint,
            to: closingMidpoint
        ))
        sampledPoints.append(contentsOf: sampleQuadCurve(
            from: closingMidpoint,
            control: firstPoint,
            to: firstPoint
        ))

        if let lastSample = sampledPoints.last, distance(from: lastSample, to: firstPoint) < 0.5 {
            sampledPoints.removeLast()
        }

        return sampledPoints
    }

    private func sampleQuadCurve(from startPoint: CGPoint, control: CGPoint, to endPoint: CGPoint) -> [CGPoint] {
        let sampleCount = max(10, min(32, Int(distance(from: startPoint, to: endPoint) / 8)))
        var points: [CGPoint] = []
        points.reserveCapacity(sampleCount)

        for step in 1...sampleCount {
            let t = CGFloat(step) / CGFloat(sampleCount)
            let inverseT = 1 - t

            let startWeight = inverseT * inverseT
            let controlWeight = 2 * inverseT * t
            let endWeight = t * t

            let x = startWeight * startPoint.x + controlWeight * control.x + endWeight * endPoint.x
            let y = startWeight * startPoint.y + controlWeight * control.y + endWeight * endPoint.y
            points.append(CGPoint(x: x, y: y))
        }

        return points
    }

    private func distance(from startPoint: CGPoint, to endPoint: CGPoint) -> CGFloat {
        hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
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

    private func absolutePoint(_ point: NormalizedPoint, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.minX + frame.width * CGFloat(point.x),
            y: frame.minY + frame.height * CGFloat(point.y)
        )
    }

    private func normalizedPoint(_ point: CGPoint, in frame: CGRect) -> NormalizedPoint {
        NormalizedPoint(
            x: Double((point.x - frame.minX) / frame.width),
            y: Double((point.y - frame.minY) / frame.height)
        )
    }
}
