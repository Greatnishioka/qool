import CoreGraphics

struct CanvasElementFactory {

    /**
    * 指定されたツールに基づいて、キャンバス要素を作成します。
    */
    func makeElement(for tool: CanvasTool, at origin: CGPoint? = nil) -> CanvasElement? {

        // 要素のフレームを、指定された原点を中心に配置するためのヘルパー関数
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

        // 選択ツールは新しい要素を作成しないため、nil を返す。
        case .select:
            return nil

        // 矩形 (四角形) の場合。
        case .rectangle:
            return CanvasElement(
                kind: .rectangle,
                frame: centeredFrame(width: 180, height: 120),
                fillColor: .paper
            )
        
        // パス (フリーハンドの線) の場合。
        case .path:
            return CanvasElement(
                kind: .path,
                frame: centeredFrame(width: 190, height: 110),
                fillColor: .sky
            )

        // 直線のツールの場合。
        case .line:
            return CanvasElement(
                kind: .line,
                frame: centeredFrame(width: 180, height: 28),
                fillColor: .clear,
                strokeWidth: 4
            )

        // テキストツールの場合。
        case .text:
            return CanvasElement(
                kind: .text,
                frame: centeredFrame(width: 180, height: 64),
                fillColor: .clear,
                strokeWidth: 0,
                showsStroke: false,
                text: "テキスト"
            )

        // 画像ツールの場合。
        // 現時点では、未実装
        case .image:
            return CanvasElement(
                kind: .imageCutout,
                frame: centeredFrame(width: 200, height: 160),
                fillColor: .coral
            )
        }
    }
}
