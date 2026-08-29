import CoreGraphics
import Foundation

nonisolated struct CanvasDraftElementBuilder {
    init() {}

    func makeElement(for tool: CanvasTool, from start: CGPoint, to current: CGPoint) -> CanvasElement? {
        switch tool {
        case .select, .path:
            return nil
        case .rectangle:
            return CanvasElement(
                kind: .rectangle,
                frame: normalizedFrame(from: start, to: current, minimumSize: CGSize(width: 1, height: 1)),
                fillColor: .paper
            )
        case .line:
            let dx = current.x - start.x
            let dy = current.y - start.y
            let length = max(1, hypot(dx, dy))
            let center = CGPoint(x: start.x + dx / 2, y: start.y + dy / 2)
            let angle = atan2(dy, dx) * 180 / .pi

            return CanvasElement(
                kind: .line,
                frame: CGRect(x: center.x - length / 2, y: center.y - 14, width: length, height: 28),
                fillColor: .clear,
                strokeWidth: 4,
                rotationAngleDegrees: angle
            )
        case .text:
            return CanvasElement(
                kind: .text,
                frame: normalizedFrame(from: start, to: current, minimumSize: CGSize(width: 1, height: 1)),
                fillColor: .clear,
                strokeWidth: 0,
                showsStroke: false,
                text: "テキスト"
            )
        case .image:
            return CanvasElement(
                kind: .imageCutout,
                frame: normalizedFrame(from: start, to: current, minimumSize: CGSize(width: 1, height: 1)),
                fillColor: .coral
            )
        }
    }

    func makePathElement(from points: [CGPoint], isClosed: Bool) -> CanvasElement? {
        guard let firstPoint = points.first else {
            return nil
        }

        let bounds = points.dropFirst().reduce(CGRect(origin: firstPoint, size: .zero)) { partialResult, point in
            partialResult.union(CGRect(origin: point, size: .zero))
        }
        let frame = bounds.insetBy(dx: -8, dy: -8)
        let safeFrame = CGRect(
            x: frame.minX,
            y: frame.minY,
            width: max(frame.width, 16),
            height: max(frame.height, 16)
        )
        let pathPoints = points.map { point in
            NormalizedPoint(
                x: Double((point.x - safeFrame.minX) / safeFrame.width),
                y: Double((point.y - safeFrame.minY) / safeFrame.height)
            )
        }

        return CanvasElement(
            kind: .path,
            frame: safeFrame,
            fillColor: .sky,
            strokeColor: .ink,
            strokeWidth: 2,
            showsStroke: true,
            pathPoints: pathPoints,
            isClosedPath: isClosed
        )
    }

    func isDrawable(_ element: CanvasElement) -> Bool {
        switch element.kind {
        case .line:
            element.frame.width >= 8
        case .rectangle, .path, .text, .imageCutout:
            element.frame.width >= 8 && element.frame.height >= 8
        }
    }

    private func normalizedFrame(from start: CGPoint, to current: CGPoint, minimumSize: CGSize) -> CGRect {
        let minX = min(start.x, current.x)
        let minY = min(start.y, current.y)
        let width = max(abs(current.x - start.x), minimumSize.width)
        let height = max(abs(current.y - start.y), minimumSize.height)

        return CGRect(x: minX, y: minY, width: width, height: height)
    }
}
