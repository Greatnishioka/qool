import CoreGraphics

struct CanvasElementFactory {
    func makeElement(for tool: CanvasTool) -> CanvasElement? {
        switch tool {
        case .select:
            nil
        case .rectangle:
            CanvasElement(
                kind: .rectangle,
                frame: CGRect(x: 64, y: 96, width: 180, height: 120),
                fillColor: .paper
            )
        case .curve:
            CanvasElement(
                kind: .curve,
                frame: CGRect(x: 96, y: 140, width: 180, height: 96),
                fillColor: .sky
            )
        case .textPath:
            CanvasElement(
                kind: .textPath,
                frame: CGRect(x: 72, y: 88, width: 220, height: 140),
                fillColor: .mint
            )
        case .image:
            CanvasElement(
                kind: .imageCutout,
                frame: CGRect(x: 80, y: 120, width: 200, height: 160),
                fillColor: .coral
            )
        }
    }
}
