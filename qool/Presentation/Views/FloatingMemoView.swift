import SwiftUI

/// デスクトップに貼ったメモの中身。輪郭でマスクするため、**四角い背景を描いてはいけません。**
struct FloatingMemoView: View {
    let memo: Memo
    let outline: FloatingMemoOutline
    let imageStore: CanvasImageStore
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        GeometryReader { proxy in
            content
                .frame(width: outline.bounds.width, height: outline.bounds.height, alignment: .topLeading)
                .mask {
                    MultiContourPathShape(contours: outline.contours)
                        .fill(style: FillStyle(eoFill: true))
                }
                .scaleEffect(proxy.size.width / outline.bounds.width, anchor: .topLeading)
        }
        .contextMenu {
            Button("編集", action: onEdit)
            Button("デスクトップからはがす", action: onRemove)
        }
    }

    private var content: some View {
        ZStack(alignment: .topLeading) {
            // 切り抜き画像の抜けた部分から背面が透けないように、紙の色で埋めます。
            Color.white

            elements
        }
    }

    /// 要素はキャンバス座標のまま置かれるので、外接矩形の分だけずらして左上へ寄せます。
    private var elements: some View {
        ZStack(alignment: .topLeading) {
            ForEach(memo.canvas.elements) { element in
                CanvasElementView(
                    element: element,
                    isSelected: false,
                    image: element.imageAssetID.flatMap { imageStore.image(for: $0, in: memo.id) }
                )
            }
        }
        .frame(width: outline.bounds.width, height: outline.bounds.height, alignment: .topLeading)
        .offset(x: -outline.bounds.minX, y: -outline.bounds.minY)
    }
}
