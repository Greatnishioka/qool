import Foundation

/// 選んだ範囲に書式を当て、**本文と選択の両方**を返す。
///
/// **キャンバスと、デスクトップに貼ったメモの両方から使います**
/// （[#21](https://github.com/Greatnishioka/qool/issues/21) の段階 5）。
/// 呼び分けを 2 箇所に書くと、記法の扱いを直したときに片方だけ古くなります。
///
/// **選択も返すのが要点です。** 記号を足した分だけ位置がずれるので、
/// そのままにすると続けて別の書式を重ねられません。
///
/// 記法を切らないための補正は、ユースケースの中で行っています
/// （[MarkdownSyntaxBoundary](../../Application/UseCases/Text/MarkdownSyntaxBoundary.swift)）。
nonisolated struct RichTextStyling {
    private let toggleInlineStyle = ToggleInlineMarkdownStyleUseCase()
    private let applyColor = ApplyMarkdownColorUseCase()

    init() {}

    func applying(
        _ style: InlineMarkdownStyle,
        to markdown: String,
        selection: NSRange
    ) -> (markdown: String, selection: NSRange) {
        let result = toggleInlineStyle(markdown, selection: selection, style: style)

        return (result.markdown, result.selection)
    }

    func applying(
        _ color: RGBAComponents?,
        to markdown: String,
        selection: NSRange
    ) -> (markdown: String, selection: NSRange) {
        let result = applyColor(markdown, selection: selection, color: color)

        return (result.markdown, result.selection)
    }
}
