import AppKit
import SwiftUI

/// 要素の本文を表示し、編集中なら書き換えられるようにする。
///
/// **表示と編集で同じビューを使います。** 別々に作ると、編集に入った瞬間に
/// 折り返しや行間が変わって文字が飛びます。`isEditing` で振る舞いだけを切り替えます。
///
/// 装飾はまだ付けません（[#21](https://github.com/Greatnishioka/qool/issues/21) の段階 3）。
/// ここで固定するのは**生の Markdown を抱えたまま編集できること**だけです。
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// 選択。**両方向です。** 道具から書式を付けると、中身と一緒に選択も戻ってきます。
    @Binding var selection: NSRange
    var isEditing: Bool
    var font: NSFont
    var textColor: NSColor
    var onEndEditing: () -> Void
    /// 選択が動いた。**道具を浮かせる場所**を要素の中の座標で渡します。
    var onSelectionGeometry: (CGRect?) -> Void = { _ in }

    private let sync = MarkdownEditingSync()

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView.make()
        // **見た目を先に決めます。** `string` を入れると選択が動いたことになり、
        // その場で装飾が走ります。先に delegate を付けると、**既定の 13pt で当たります**
        // （記録で確認しました）。
        textView.currentStyle = style
        textView.string = text
        textView.font = font
        textView.textColor = textColor
        textView.delegate = context.coordinator
        textView.onEndEditing = onEndEditing
        textView.onCompositionChange = { [weak textView] in
            context.coordinator.compositionDidChange(in: textView)
        }
        // **装飾より先に決めます。** `NSTextView` は既定で編集できるので、
        // ここを飛ばすと最初の 1 回だけ「編集中」として記法が見えたまま残ります。
        textView.isEditable = isEditing
        textView.isSelectable = isEditing
        context.coordinator.decorate(textView, style: style)

        // **スクロールビューに入れると、大きさは自分で決めることになります。**
        // SwiftUI に直接置いていたときは向こうが決めてくれていました。
        // 書かないとテキストビューが 0×0 のままで、文字が 1 つも描かれません。
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        // 横はスクロールビューに合わせ、縦は中身の量で伸びます。
        textView.autoresizingMask = [.width]

        // **溢れた分はスクロールで見せます。** 枠を伸ばすと外形が毎回変わり、
        // 貼ったメモの形とウィンドウの大きさまで計算し直すことになります。
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        // **重ねる形にします。** 「スクロールバーを常に表示」の設定だと、
        // 帯がずっと出たままになり、枠なしのメモに四角い線が乗ります。
        scrollView.scrollerStyle = .overlay

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? MarkdownTextView else {
            return
        }

        context.coordinator.text = $text
        textView.onEndEditing = onEndEditing

        // **`textView.font` と `textView.textColor` は使いません。**
        // setter は本文全体を塗り替え、getter は先頭の文字の値を返します。
        // 記法を潰すと先頭が 0.01pt になるため、次の更新で「違う」と判断されて
        // **自分で当てた装飾を自分で消していました**（記録で確認しました）。
        // 本文の書体と色は装飾がまとめて当てるので、ここでは触りません。
        if textView.currentStyle.baseFont != font || textView.currentStyle.baseColor != textColor {
            context.coordinator.invalidateDecoration()
        }

        context.coordinator.selection = $selection
        context.coordinator.onSelectionGeometry = onSelectionGeometry

        applyExternalText(to: textView, context: context)
        applyExternalSelection(to: textView, context: context)
        applyEditability(to: textView)
        context.coordinator.decorate(textView, style: style)
    }

    /// 表示の決まりごと。**要素の色を既定にし、`<span>` が上書きします。**
    private var style: RichTextStyle {
        RichTextStyle(baseFont: font, baseColor: textColor)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selection: $selection)
    }

    /// 外から来た文字列を流し込む。**選択は入る範囲まで戻します。**
    private func applyExternalText(to textView: MarkdownTextView, context: Context) {
        guard sync.shouldApply(
            external: text,
            current: textView.string,
            isComposing: textView.isComposing
        ) else {
            return
        }

        let selection = textView.selectedRange()
        context.coordinator.allowExternalSelection()
        context.coordinator.invalidateDecoration()
        textView.string = text
        textView.setSelectedRange(sync.preservedSelection(selection, in: text))
    }

    /// 外から来た選択を合わせる。**道具で書式を付けたあとに戻ってきます。**
    private func applyExternalSelection(to textView: MarkdownTextView, context: Context) {
        let current = textView.selectedRange()
        let wanted = sync.preservedSelection(selection, in: textView.string)

        // **自分が出した選択が返ってきただけなら触りません。**
        // なぞっている最中に当て直すと、選択がその場で潰れて広げられなくなります。
        guard !textView.isComposing,
              current != wanted,
              context.coordinator.lastPublishedSelection != selection else {
            return
        }

        textView.setSelectedRange(wanted)
    }

    /// 編集できるかを合わせる。
    ///
    /// **入力を受け取る役は次の間合いで渡します。** 描画の最中に
    /// `makeFirstResponder` を呼ぶと、その場で走る再描画と噛み合いません。
    private func applyEditability(to textView: MarkdownTextView) {
        textView.isEditable = isEditing
        textView.isSelectable = isEditing

        let isFocused = textView.window?.firstResponder === textView

        guard isEditing != isFocused else {
            return
        }

        Task { @MainActor in
            guard let window = textView.window else {
                return
            }

            if isEditing {
                window.makeFirstResponder(textView)
            } else if window.firstResponder === textView {
                window.makeFirstResponder(nil)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var selection: Binding<NSRange>
        var onSelectionGeometry: (CGRect?) -> Void = { _ in }
        /// 直前に外へ出した選択。**返ってきたものを当て直さない**ために覚えます。
        private(set) var lastPublishedSelection: NSRange?

        private let builder = MarkdownAttributedTextBuilder()
        private let selectionGuard = MarkdownSelectionGuard()
        /// 直前に当てた組み合わせ。**同じなら当て直しません。**
        /// 選択が動くたびに全文へ属性を貼ると、レイアウトが毎回作り直されます。
        private var lastDecoration: (text: String, active: NSRange)?

        init(text: Binding<String>, selection: Binding<NSRange>) {
            self.text = text
            self.selection = selection
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else {
                return
            }

            publish(from: textView)
        }

        /// **選択が変わるたびに必ず通ります。** ドラッグでも矢印キーでも、
        /// ダブルクリックでも、プログラムから動かしたときでも。
        /// ここで端を記法の外へ寄せれば、**下流はきれいな範囲しか受け取りません。**
        func textView(
            _ textView: NSTextView,
            willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
            toCharacterRange newSelectedCharRange: NSRange
        ) -> NSRange {
            guard let markdownTextView = textView as? MarkdownTextView else {
                return newSelectedCharRange
            }

            return selectionGuard.selection(
                newSelectedCharRange,
                movingFrom: oldSelectedCharRange,
                avoiding: markdownTextView.hiddenSyntaxRanges,
                length: (textView.string as NSString).length
            )
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else {
                return
            }

            decorate(textView, style: textView.currentStyle)
            publishSelection(from: textView)
        }

        /// 選択と、その場所を外へ出す。
        ///
        /// **表示だけのときは出しません。** 道具が出たままになります。
        private func publishSelection(from textView: MarkdownTextView) {
            guard textView.isEditable, !textView.isComposing else {
                onSelectionGeometry(nil)
                return
            }

            let range = textView.selectedRange()

            lastPublishedSelection = range

            if selection.wrappedValue != range {
                selection.wrappedValue = range
            }

            guard range.length > 0, let rect = textView.selectionLineRect() else {
                onSelectionGeometry(nil)
                return
            }

            onSelectionGeometry(textView.convert(rect, to: textView.enclosingScrollView))
        }

        /// 装飾を当て直す。
        ///
        /// **変換中は触りません。** 途中の文字列へ属性を貼ると変換が中断されます。
        /// 外から選択を入れ直してよい状態へ戻す。**道具で書式を付けたあと**に呼びます。
        func allowExternalSelection() {
            lastPublishedSelection = nil
        }

        /// 装飾の覚えを捨てる。
        ///
        /// **`string` を入れ直すと属性が全部落ちます。** 覚えたままだと
        /// 「同じ内容だから当て直さなくてよい」と判断して、**生の記法が出たままになります。**
        func invalidateDecoration() {
            lastDecoration = nil
        }

        func decorate(_ textView: MarkdownTextView, style: RichTextStyle) {
            guard !textView.isComposing, let storage = textView.textStorage else {
                return
            }

            textView.currentStyle = style

            let markdown = textView.string
            let selection = textView.isEditable ? textView.selectedRange() : nil
            let active = MarkdownAttributedTextBuilder.activeRange(
                for: selection ?? NSRange(location: 0, length: 0),
                in: markdown as NSString
            )
            let key = (text: markdown, active: selection == nil ? NSRange(location: NSNotFound, length: 0) : active)

            if let lastDecoration, lastDecoration.text == key.text, lastDecoration.active == key.active {
                return
            }

            lastDecoration = key

            let decoration = builder.decoration(
                markdown: markdown,
                selection: selection,
                style: style
            )
            let decorated = decoration.text
            textView.hiddenSyntaxRanges = decoration.hiddenSyntaxRanges
            let full = NSRange(location: 0, length: storage.length)

            storage.beginEditing()
            decorated.enumerateAttributes(in: full) { attributes, range, _ in
                storage.setAttributes(attributes, range: range)
            }
            storage.endEditing()

            // **次に打つ文字が潰れた記法の書体を引き継がないようにします。**
            // 隠した記法のすぐ後ろにキャレットがあると、0.01pt の透明な文字になります。
            textView.typingAttributes = [
                .font: style.baseFont,
                .foregroundColor: style.baseColor
            ]
        }

        /// 変換が終わった瞬間にも出します。
        ///
        /// **`textDidChange` は変換中も飛んできます。** そこで出すと、返ってきた反映で
        /// 変換が中断されます。確定するまで待ってから出します。
        func compositionDidChange(in textView: MarkdownTextView?) {
            guard let textView, !textView.isComposing else {
                return
            }

            publish(from: textView)
        }

        private func publish(from textView: MarkdownTextView) {
            guard !textView.isComposing, text.wrappedValue != textView.string else {
                return
            }

            text.wrappedValue = textView.string
        }
    }
}
