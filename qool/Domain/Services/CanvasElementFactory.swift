import CoreGraphics

nonisolated struct CanvasElementFactory {
    func makeElement(for tool: CanvasTool, at origin: CGPoint? = nil) -> CanvasElement? {
        func centeredFrame(width: CGFloat, height: CGFloat) -> CGRect {
            let point = origin ?? CGPoint(x: 160, y: 160)
            return CGRect(
                x: point.x - width / 2,
                y: point.y - height / 2,
                width: width,
                height: height
            )
        }

        switch tool {
        case .select:
            return nil
        case .rectangle:
            return CanvasElement(
                kind: .rectangle,
                frame: centeredFrame(width: 180, height: 120),
                fillColor: .paper
            )
        case .path:
            return CanvasElement(
                kind: .path,
                frame: centeredFrame(width: 190, height: 110),
                fillColor: .sky
            )
        case .line:
            return CanvasElement(
                kind: .line,
                frame: centeredFrame(width: 180, height: 28),
                fillColor: .clear,
                strokeWidth: 4
            )
        case .text:
            return CanvasElement(
                kind: .text,
                frame: centeredFrame(width: 180, height: 64),
                fillColor: .clear,
                strokeWidth: 0,
                showsStroke: false,
                text: "テキスト"
            )
        // 画像は現時点では未実装。矩形と同じ扱いで枠だけ置いている。
        case .image:
            return CanvasElement(
                kind: .imageCutout,
                frame: centeredFrame(width: 200, height: 160),
                fillColor: .coral
            )
        }
    }
}
