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
    var isEditing: Bool
    var font: NSFont
    var textColor: NSColor
    var onEndEditing: () -> Void

    private let sync = MarkdownEditingSync()

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView.make()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = font
        textView.textColor = textColor
        textView.onEndEditing = onEndEditing
        textView.onCompositionChange = { [weak textView] in
            context.coordinator.compositionDidChange(in: textView)
        }
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

        if textView.font != font {
            textView.font = font
        }

        if textView.textColor != textColor {
            textView.textColor = textColor
        }

        applyExternalText(to: textView)
        applyEditability(to: textView)
        context.coordinator.decorate(textView, style: style)
    }

    /// 表示の決まりごと。**要素の色を既定にし、`<span>` が上書きします。**
    private var style: RichTextStyle {
        RichTextStyle(baseFont: font, baseColor: textColor)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    /// 外から来た文字列を流し込む。**選択は入る範囲まで戻します。**
    private func applyExternalText(to textView: MarkdownTextView) {
        guard sync.shouldApply(
            external: text,
            current: textView.string,
            isComposing: textView.isComposing
        ) else {
            return
        }

        let selection = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(sync.preservedSelection(selection, in: text))
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

        private let builder = MarkdownAttributedTextBuilder()
        /// 直前に当てた組み合わせ。**同じなら当て直しません。**
        /// 選択が動くたびに全文へ属性を貼ると、レイアウトが毎回作り直されます。
        private var lastDecoration: (text: String, active: NSRange)?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else {
                return
            }

            publish(from: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else {
                return
            }

            decorate(textView, style: textView.currentStyle)
        }

        /// 装飾を当て直す。
        ///
        /// **変換中は触りません。** 途中の文字列へ属性を貼ると変換が中断されます。
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

            let decorated = builder.attributedString(
                markdown: markdown,
                selection: selection,
                style: style
            )
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
