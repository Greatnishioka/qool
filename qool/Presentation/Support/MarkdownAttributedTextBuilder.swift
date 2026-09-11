import AppKit

/// 生の Markdown に、意味に応じた属性を重ねる。
///
/// **文字列は変えません。** 返すのは同じ文字列に属性だけを載せたもので、
/// `NSTextView` の中身と一字一句同じままです
/// （[#21](https://github.com/Greatnishioka/qool/issues/21) の不変条件）。
///
/// **記法の文字はカーソルのあるブロックでだけ見せます。** 全部隠すと書き換えられず、
/// 全部見せると Markdown のソースを読んでいるのと変わりません。
nonisolated struct MarkdownAttributedTextBuilder {
    private let parser: any MarkdownParserProtocol

    init(parser: any MarkdownParserProtocol = SwiftMarkdownParserInfrastructure()) {
        self.parser = parser
    }

    /// - Parameter selection: 今の選択。**ここと重なるブロックだけ記法を見せます。**
    ///   編集していないときは `nil` を渡すと、どこも見せません。
    func attributedString(
        markdown: String,
        selection: NSRange?,
        style: RichTextStyle
    ) -> NSAttributedString {
        let source = markdown as NSString
        let full = NSRange(location: 0, length: source.length)
        let result = NSMutableAttributedString(string: markdown)

        result.setAttributes([.font: style.baseFont, .foregroundColor: style.baseColor], range: full)

        let spans = parser.spans(in: markdown)
        let active = selection.map { Self.activeRange(for: $0, in: source) }

        // **記法は最後に当てます。** 先に当てると、太字や見出しの書体で
        // 潰した大きさが戻ってしまいます。
        for span in spans where span.kind != .syntax {
            let attributes = style.attributes(for: span.kind, base: baseFont(at: span.range, in: result, style: style))
            result.addAttributes(attributes, range: span.range)
        }

        for span in spans where span.kind == .syntax {
            let isVisible = active.map { NSIntersectionRange($0, span.range).length > 0 || $0.location == span.range.location } ?? false
            result.addAttributes(
                isVisible ? style.visibleSyntaxAttributes() : style.hiddenSyntaxAttributes(),
                range: span.range
            )
        }

        return result
    }

    /// 記法を見せる範囲。**ソース上の段落**で切ります。
    ///
    /// **折り返した行ではありません。** 見た目の行で切ると、記法が出た瞬間に
    /// 折り返しが変わってキャレットが跳ねます。
    static func activeRange(for selection: NSRange, in source: NSString) -> NSRange {
        let clamped = NSRange(
            location: min(selection.location, source.length),
            length: min(selection.length, max(0, source.length - min(selection.location, source.length)))
        )

        guard source.length > 0 else {
            return clamped
        }

        return source.paragraphRange(for: clamped)
    }

    /// その位置に既に載っている書体。**太字の中の斜体を両立させる**ために見ます。
    private func baseFont(
        at range: NSRange,
        in text: NSAttributedString,
        style: RichTextStyle
    ) -> NSFont {
        guard range.location < text.length else {
            return style.baseFont
        }

        return text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? style.baseFont
    }
}
