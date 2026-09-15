import Foundation

/// 本文の一部に付いている意味。
///
/// **表示の属性ではありません。** `NSFont` や `NSColor` へ写すのは Presentation の仕事で、
/// ここでは「何であるか」だけを持ちます（[#21](https://github.com/Greatnishioka/qool/issues/21)）。
nonisolated enum RichTextSpanKind: Equatable, Hashable {
    case strong
    case emphasis
    case strikethrough
    case inlineCode
    case link(destination: String)
    case heading(level: Int)
    /// 箇条書き・番号付き・チェックボックスの中身。
    /// - Parameter ordinal: 番号付きなら番号。箇条書きなら `nil`。
    /// - Parameter isChecked: チェックボックスなら状態。ふつうの項目なら `nil`。
    case listItem(ordinal: Int?, isChecked: Bool?)
    case color(RGBAComponents)

    /// 箇条書きの `- `、番号の `1. `、チェックの `- [x] `。
    ///
    /// **記法ですが隠しません。** これ自体が箇条書きの目印で、
    /// 潰すと**ただの段落に見えます**（実際に見えなくなっていました）。
    /// 文字列は変えられないので、記号をそのまま見せます。
    case listMarker

    /// 記法そのものの文字。`**` や `# `、`<span ...>` がこれにあたります。
    ///
    /// **これを持たないと WYSIWYG になりません。** 生の Markdown を抱えたまま
    /// 記法だけを薄くしたり隠したりするには、どの文字が記法なのかが要ります。
    case syntax
}
