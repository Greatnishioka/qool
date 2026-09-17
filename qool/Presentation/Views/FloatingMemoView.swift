import AppKit
import SwiftUI

/// 机の上の付箋の中身。輪郭でマスクするため、**四角い背景を描いてはいけません。**
struct FloatingMemoView: View {
    /// 描く内容。**雛形の形に、この付箋の本文を差し込んだもの**です
    /// （[#29](https://github.com/Greatnishioka/qool/issues/29)）。
    let canvas: Canvas
    /// 画像アセットの持ち主。**雛形です。** 付箋は自分の画像を持たず、
    /// 雛形の名前空間をそのまま使います。
    let templateID: Memo.ID
    let outline: FloatingMemoOutline
    let imageStore: CanvasImageStore
    @ObservedObject var maskStore: CutoutMaskStore
    let onEdit: () -> Void
    let onRemove: () -> Void
    /// 本文を書き換えた。**保存は貼る側が引き受けます。**
    let onTextChange: (CanvasElement.ID, String) -> Void
    /// 書き換えに入った／抜けた。**入っている間は窓を作り直させません。**
    let onEditingChange: (Bool) -> Void
    /// 書式の道具を出す／引っ込める。**主の印を添えます。**
    /// 添えないと、別の窓が出した道具まで引っ込めてしまいます。
    let onToolbar: (UUID, RichTextToolbarRequest?) -> Void

    /// 書き換えている要素。**このビューの中に持ちます。**
    ///
    /// 貼る側に持たせると、編集に入るたびに `rootView` が差し替わります。
    /// 差し替えはテキストビューを当て直す引き金なので、**入った瞬間にキャレットが飛びます**
    /// （[#21](https://github.com/Greatnishioka/qool/issues/21) の段階 5）。
    @State private var editingElementID: CanvasElement.ID?
    @State private var textSelection = NSRange(location: 0, length: 0)

    /// 書き換えている本文。**書き換え中はこれが正です。**
    ///
    /// `memo` は窓を作った時点の写しで、書き換え中はわざと更新しません（上記の理由）。
    /// **写しの本文をそのまま渡すと、打った字が即座に消えます。**
    /// 選択が動くたびに `body` が走り直し、古い本文が「外から来た新しい値」として
    /// 流し込まれるためです。
    @State private var editingText: String?

    /// 道具を出した主を見分ける印。**貼ったメモは何枚でも出せます。**
    @State private var toolbarOwner = UUID()

    /// **選択の位置は持ちません。** スクロール中は毎フレーム変わるので、
    /// `@State` に入れると打つたび・送るたびにこのメモ全体が描き直されます
    /// （キャンバス側で同じことをして重くなりました）。受け取ってそのまま流します。
    private let styling = RichTextStyling()

    var body: some View {
        GeometryReader { proxy in
            content
                .frame(width: outline.bounds.width, height: outline.bounds.height, alignment: .topLeading)
                .scaleEffect(proxy.size.width / outline.bounds.width, anchor: .topLeading)
        }
        .contextMenu {
            Button("雛形を編集", action: onEdit)
            Button("この付箋をはがす", action: onRemove)
        }
    }

    /// **ウィンドウ側で切り抜きません。** 要素はそれぞれ自分のマスクでぼけた形に描かれるので、
    /// ここで輪郭に沿って切ると、ぼかした縁が硬い縁に戻ります。
    /// クリックの素通しは [ContourHostingView](../../Infrastructure/AppKit/ContourHostingView.swift)
    /// が輪郭多角形で行うため、見た目のマスクは要りません。
    private var content: some View {
        ZStack(alignment: .topLeading) {
            // 切り抜き画像の抜けた部分から背面が透けないように、紙の色で埋めます。
            // **余白とぼかしを除いた形に敷きます。** 広げた形に敷くとぼかしが隠れます。
            MultiContourPathShape(contours: outline.paperContours)
                .fill(Color.white, style: FillStyle(eoFill: true))

            elements
            textHitAreas
        }
    }

    /// 要素はキャンバス座標のまま置かれるので、外接矩形の分だけずらして左上へ寄せます。
    private var elements: some View {
        elementSpace {
            ForEach(canvas.elements) { element in
                CanvasElementView(
                    element: edited(element),
                    isSelected: false,
                    image: element.imageAssetID.flatMap { imageStore.image(for: $0, in: templateID) },
                    drawingMask: maskStore.drawingMask(for: element, in: templateID),
                    textEditing: textEditing(for: element)
                )
            }
        }
    }

    /// 書き換えに入るための当たり判定。
    ///
    /// **要素そのものには付けられません。** `CanvasElementView` は書き換え中以外
    /// クリックを受け取らない作りです（キャンバスでは背景の 1 つのジェスチャに集約しています）。
    /// 貼ったメモにはその背景がないので、本文の上にだけ入口を置きます。
    ///
    /// **本文の外には置きません。** 置くと余白のドラッグをここが食べてしまい、
    /// ウィンドウを掴んで動かせなくなります。
    private var textHitAreas: some View {
        elementSpace {
            ForEach(canvas.elements.filter { $0.kind == .text }) { element in
                Color.clear
                    .frame(width: element.frame.width, height: max(2, element.frame.height))
                    .contentShape(Rectangle())
                    .rotationEffect(.degrees(element.rotationAngleDegrees))
                    .position(x: element.frame.midX, y: element.frame.midY)
                    // 書き換えている本人の上では退きます。退かないと文字を選べません。
                    .allowsHitTesting(editingElementID != element.id)
                    .onTapGesture(count: 2) { beginEditing(element) }
            }
        }
    }

    /// キャンバス座標のまま置いた要素を、外接矩形の左上へ寄せる入れ物。
    private func elementSpace<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            content()
        }
        .frame(width: outline.bounds.width, height: outline.bounds.height, alignment: .topLeading)
        .offset(x: -outline.bounds.minX, y: -outline.bounds.minY)
    }

    /// 書き換え中の要素には、打っている本文を差し込む。
    private func edited(_ element: CanvasElement) -> CanvasElement {
        guard element.id == editingElementID, let editingText else {
            return element
        }

        var updated = element
        updated.text = editingText

        return updated
    }

    private func textEditing(for element: CanvasElement) -> CanvasTextEditing? {
        guard element.kind == .text else {
            return nil
        }

        return CanvasTextEditing(
            isEditing: editingElementID == element.id,
            selection: $textSelection,
            onChange: { text in
                editingText = text
                onTextChange(element.id, text)
            },
            onEndEditing: endEditing,
            onSelectionGeometry: publishToolbar
        )
    }

    /// 選んだ範囲の上に道具を出す。**範囲が無ければ引っ込めます。**
    private func publishToolbar(_ selectionRect: CGRect?) {
        guard editingElementID != nil, let selectionRect else {
            onToolbar(toolbarOwner, nil)

            return
        }

        onToolbar(
            toolbarOwner,
            RichTextToolbarRequest(
                selectionRect: selectionRect,
                onStyle: { style in applyTextEdit { styling.applying(style, to: $0, selection: $1) } },
                onColor: { color in applyTextEdit { styling.applying(color, to: $0, selection: $1) } }
            )
        )
    }

    /// 書式を当てて、**本文と選択の両方**を書き戻す。
    ///
    /// **選択も戻すのが要点です。** 記号を足した分だけ位置がずれるので、
    /// そのままにすると続けて別の書式を重ねられません。
    private func applyTextEdit(_ edit: (String, NSRange) -> (String, NSRange)) {
        guard let elementID = editingElementID, let current = editingText else {
            return
        }

        let (markdown, selection) = edit(current, textSelection)

        guard markdown != current else {
            return
        }

        editingText = markdown
        textSelection = selection
        onTextChange(elementID, markdown)
    }

    private func beginEditing(_ element: CanvasElement) {
        guard editingElementID != element.id else {
            return
        }

        editingElementID = element.id
        editingText = element.text
        textSelection = NSRange(location: 0, length: 0)
        onEditingChange(true)
    }

    private func endEditing() {
        guard editingElementID != nil else {
            return
        }

        editingElementID = nil
        editingText = nil
        onToolbar(toolbarOwner, nil)
        onEditingChange(false)
    }
}
