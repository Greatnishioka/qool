import AppKit
import Foundation
import Testing
@testable import qool

/// 選択した範囲の書式を付け外しする処理の検証。
///
/// **書き換えるのは生の Markdown の文字列だけです。** 表示の属性は触りません。
struct MarkdownStyleEditingTests {
    private let toggle = ToggleInlineMarkdownStyleUseCase()
    private let applyColor = ApplyMarkdownColorUseCase()
    private let builder = MarkdownAttributedTextBuilder()
    private let style = RichTextStyle(baseFont: .systemFont(ofSize: 20), baseColor: .black)

    private func color(_ markdown: String, at needle: String) -> NSColor? {
        let index = (markdown as NSString).range(of: needle).location

        return builder.attributedString(markdown: markdown, selection: nil, style: style)
            .attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    private func range(_ text: String, _ substring: String) -> NSRange {
        (text as NSString).range(of: substring)
    }

    // MARK: - 付ける

    @Test func 選んだ範囲を太字にする() {
        let markdown = "これは太字になる"
        let result = toggle(markdown, selection: range(markdown, "太字"), style: .strong)

        #expect(result.markdown == "これは**太字**になる")
    }

    /// **記号は選び直しません。** 中身が選ばれたままなら、続けて別の書式を重ねられます。
    @Test func 付けたあとも中身が選ばれている() {
        let markdown = "これは太字になる"
        let result = toggle(markdown, selection: range(markdown, "太字"), style: .strong)
        let selected = (result.markdown as NSString).substring(with: result.selection)

        #expect(selected == "太字")
    }

    @Test func 太字の上から斜体も重ねられる() {
        let markdown = "あ太字い"
        let bold = toggle(markdown, selection: range(markdown, "太字"), style: .strong)
        let italic = toggle(bold.markdown, selection: bold.selection, style: .emphasis)

        #expect(italic.markdown == "あ***太字***い")
    }

    @Test func 何も選んでいなければ記号だけ入る() {
        let result = toggle("あい", selection: NSRange(location: 1, length: 0), style: .strong)

        #expect(result.markdown == "あ****い")
        // 記号の間へキャレットが入ります。
        #expect(result.selection == NSRange(location: 3, length: 0))
    }

    @Test func 打ち消しとコードも同じように付く() {
        let strike = toggle("あいう", selection: range("あいう", "い"), style: .strikethrough)
        let code = toggle("あいう", selection: range("あいう", "い"), style: .inlineCode)

        #expect(strike.markdown == "あ~~い~~う")
        #expect(code.markdown == "あ`い`う")
    }

    // MARK: - 外す

    /// 中身だけを選んで押した場合。
    @Test func 外側が記号なら外す() {
        let markdown = "これは**太字**になる"
        let result = toggle(markdown, selection: range(markdown, "太字"), style: .strong)

        #expect(result.markdown == "これは太字になる")
        #expect((result.markdown as NSString).substring(with: result.selection) == "太字")
    }

    /// 記号ごと選んで押した場合。
    @Test func 内側が記号でも外す() {
        let markdown = "これは**太字**になる"
        let result = toggle(markdown, selection: range(markdown, "**太字**"), style: .strong)

        #expect(result.markdown == "これは太字になる")
        #expect((result.markdown as NSString).substring(with: result.selection) == "太字")
    }

    /// **記号の長さが違うものを取り違えません。** `**` を外そうとして `*` を消すと壊れます。
    @Test func 太字を斜体として外さない() {
        let markdown = "あ**太字**い"
        let result = toggle(markdown, selection: range(markdown, "太字"), style: .emphasis)

        #expect(result.markdown == "あ***太字***い")
    }

    // MARK: - 位置

    /// **UTF-16 で数えます。** 日本語や絵文字で位置がずれると、記号が文字の途中に入ります。
    @Test func 絵文字を挟んでも記号が正しい場所に入る() {
        let markdown = "a👨‍👩‍👧b太字c"
        let result = toggle(markdown, selection: range(markdown, "太字"), style: .strong)

        #expect(result.markdown == "a👨‍👩‍👧b**太字**c")
    }

    @Test func 範囲外の選択でも落ちない() {
        let result = toggle("みじかい", selection: NSRange(location: 999, length: 9), style: .strong)

        #expect(result.markdown == "みじかい****")
    }

    // MARK: - 文字色

    private let red = RGBAComponents(red: 1, green: 0, blue: 0)
    private let blue = RGBAComponents(red: 0, green: 0, blue: 1)

    @Test func 選んだ範囲に色を付ける() {
        let markdown = "あかくする"
        let result = applyColor(markdown, selection: range(markdown, "あか"), color: red)

        #expect(result.markdown == "<span style=\"color:#ff0000\">あか</span>くする")
    }

    @Test func 色を付けたあとも中身が選ばれている() {
        let markdown = "あかくする"
        let result = applyColor(markdown, selection: range(markdown, "あか"), color: red)
        let selected = (result.markdown as NSString).substring(with: result.selection)

        #expect(selected == "あか")
    }

    @Test func 色を外せる() {
        let markdown = "<span style=\"color:#ff0000\">あか</span>くする"
        let result = applyColor(markdown, selection: range(markdown, "あか"), color: nil)

        #expect(result.markdown == "あかくする")
    }

    /// **二重に囲みません。** 囲み直すと、外すときに 1 枚ずつしか剥がれません。
    @Test func 色を変えると囲みは1枚のまま() {
        let markdown = "<span style=\"color:#ff0000\">あか</span>くする"
        let result = applyColor(markdown, selection: range(markdown, "あか"), color: blue)

        #expect(result.markdown == "<span style=\"color:#0000ff\">あか</span>くする")
    }

    @Test func 何も選んでいなければ色は付かない() {
        let result = applyColor("あい", selection: NSRange(location: 1, length: 0), color: red)

        #expect(result.markdown == "あい")
    }

    /// **全文に色が付いていても、一部だけ別の色にできます。**
    /// 内側の囲みが外側より狭いので、あとから当たって勝ちます。
    @Test func 色の付いた本文の一部を別の色にできる() {
        let green = RGBAComponents(red: 0, green: 1, blue: 0)

        let whole = "ぜんぶあかい"
        let reddened = applyColor(whole, selection: NSRange(location: 0, length: 6), color: red)

        // 赤くした本文の「ぶあか」だけを選び直して緑にする。
        let middle = (reddened.markdown as NSString).range(of: "ぶあか")
        let mixed = applyColor(reddened.markdown, selection: middle, color: green)

        let inner = color(mixed.markdown, at: "ぶあか")?.usingColorSpace(.sRGB)
        let outer = color(mixed.markdown, at: "ぜん")?.usingColorSpace(.sRGB)

        #expect((inner?.greenComponent ?? 0) > 0.9)
        #expect((inner?.redComponent ?? 1) < 0.1)
        #expect((outer?.redComponent ?? 0) > 0.9)
        #expect((outer?.greenComponent ?? 1) < 0.1)
    }

    // MARK: - 記法を切らない

    /// **記法の途中を選んで押しても壊しません。**
    /// 見えている記法（カーソルのあるブロック）は選べてしまうので、
    /// 書式を付ける側で正します。
    @Test func タグの途中を選んでも壊れない() {
        let markdown = "<span style=\"color:#ff0000\">あか</span>"
        // 開きタグの途中まで選んだ状態。
        let result = applyColor(markdown, selection: NSRange(location: 0, length: 11), color: blue)

        #expect(result.markdown == markdown)
    }

    @Test func 記号の途中を選んで太字にしても壊れない() {
        let markdown = "あ**太字**い"
        // `*` 1 つだけを選んだ状態。
        let result = toggle(markdown, selection: NSRange(location: 1, length: 1), style: .strong)
        let hasBrokenMarker = result.markdown.contains("***")

        #expect(!hasBrokenMarker)
    }

    @Test func 記法にかからない選択はそのまま効く() {
        let markdown = "<span style=\"color:#ff0000\">あかい</span>"
        let result = toggle(markdown, selection: range(markdown, "あか"), style: .strong)

        #expect(result.markdown.contains("**あか**"))
    }

    @Test func 色の指定は6桁で書き出す() {
        let hex = ApplyMarkdownColorUseCase.hex(RGBAComponents(red: 1, green: 0.5, blue: 0))

        #expect(hex == "#ff8000")
    }
}
