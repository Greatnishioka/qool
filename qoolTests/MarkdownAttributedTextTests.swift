import AppKit
import Foundation
import Testing
@testable import qool

/// 生の Markdown へ属性を重ねる処理の検証。
///
/// **文字列を変えないことが土台です。** 記法の文字は消さず、見せ方だけを変えます。
struct MarkdownAttributedTextTests {
    private let builder = MarkdownAttributedTextBuilder()
    /// **本文は regular です。** semibold だと書体の特性として既に太字で、
    /// `**太字**` を当てても変わりません（実際に踏みました）。
    private let style = RichTextStyle(baseFont: .systemFont(ofSize: 20), baseColor: .black)

    private func decorated(_ markdown: String, selection: NSRange? = nil) -> NSAttributedString {
        builder.attributedString(markdown: markdown, selection: selection, style: style)
    }

    private func font(_ text: NSAttributedString, at index: Int) -> NSFont? {
        text.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    private func color(_ text: NSAttributedString, at index: Int) -> NSColor? {
        text.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    // MARK: - 文字列を変えない

    /// **これが崩れると設計の土台が壊れます。** 記法を消した文字列を編集して
    /// あとから Markdown へ戻す作りは採っていません。
    @Test func 文字列は生のMarkdownのまま変わらない() {
        let markdown = "# 見出し\n\n**太字**と<span style=\"color:#e05\">色</span>"

        #expect(decorated(markdown).string == markdown)
    }

    // MARK: - 装飾

    @Test func 太字は太い書体になる() {
        let text = decorated("あ**太字**い")
        // 0:「あ」 1,2:「**」 3〜:「太字」
        let bold = font(text, at: 3)
        let plain = font(text, at: 0)
        let isBold = bold?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
        let isPlain = plain?.fontDescriptor.symbolicTraits.contains(.bold) ?? false

        #expect(isBold)
        #expect(!isPlain)
    }

    @Test func 見出しは本文より大きくなる() {
        let text = decorated("## 見出し")
        let heading = font(text, at: 3)?.pointSize ?? 0

        #expect(heading > style.baseFont.pointSize)
    }

    @Test func 色の指定が文字色になる() {
        let markdown = "<span style=\"color:#ff0000\">あか</span>"
        let text = decorated(markdown)
        let index = (markdown as NSString).range(of: "あか").location
        let components = color(text, at: index)?.usingColorSpace(.sRGB)

        #expect((components?.redComponent ?? 0) > 0.99)
        #expect((components?.blueComponent ?? 1) < 0.01)
    }

    /// **内側が勝ちます。** HTML と同じで、狭いほうがあとから当たります。
    @Test func 入れ子の色は内側が勝つ() {
        let markdown = "<span style=\"color:#ff0000\">そと<span style=\"color:#0000ff\">なか</span></span>"
        let text = decorated(markdown)
        let inner = (markdown as NSString).range(of: "なか").location
        let outer = (markdown as NSString).range(of: "そと").location
        let innerColor = color(text, at: inner)?.usingColorSpace(.sRGB)
        let outerColor = color(text, at: outer)?.usingColorSpace(.sRGB)

        #expect((innerColor?.blueComponent ?? 0) > 0.9)
        #expect((innerColor?.redComponent ?? 1) < 0.1)
        #expect((outerColor?.redComponent ?? 0) > 0.9)
    }

    @Test func 太字の中の斜体は両方かかる() {
        let markdown = "**太字の中の*斜体***"
        let text = decorated(markdown)
        let index = (markdown as NSString).range(of: "斜体").location
        let traits = font(text, at: index)?.fontDescriptor.symbolicTraits

        #expect(traits?.contains(.bold) ?? false)
        #expect(traits?.contains(.italic) ?? false)
    }

    // MARK: - 記法の見せ方

    /// 編集していないときは記法を見せません。
    @Test func 選択がなければ記法は潰れる() {
        let text = decorated("あ**太字**い")
        let syntax = font(text, at: 1)?.pointSize ?? 99

        #expect(syntax < 1)
    }

    /// **カーソルのある段落だけ記法が見えます。** 全部隠すと書き換えられません。
    @Test func カーソルのある段落では記法が見える() {
        let text = decorated("あ**太字**い", selection: NSRange(location: 0, length: 0))
        let syntax = font(text, at: 1)?.pointSize ?? 0

        #expect(syntax > 1)
    }

    @Test func 別の段落の記法は潰れたまま() {
        let markdown = "**さいしょ**\n\n**つぎ**"
        let text = decorated(markdown, selection: NSRange(location: 0, length: 0))
        let firstSyntax = font(text, at: 0)?.pointSize ?? 0
        let secondSyntax = font(text, at: (markdown as NSString).range(of: "**つぎ**").location)?.pointSize ?? 99

        #expect(firstSyntax > 1)
        #expect(secondSyntax < 1)
    }

    // MARK: - 見せる範囲の切り方

    /// **折り返した行ではなく、ソース上の段落で切ります。**
    @Test func 見せる範囲は改行で区切る() {
        let source = "いちぎょうめ\nにぎょうめ\nさんぎょうめ" as NSString
        let range = MarkdownAttributedTextBuilder.activeRange(
            for: NSRange(location: 8, length: 0),
            in: source
        )
        let text = source.substring(with: range)

        #expect(text == "にぎょうめ\n")
    }

    @Test func 範囲外の選択でも落ちない() {
        let source = "みじかい" as NSString
        let range = MarkdownAttributedTextBuilder.activeRange(
            for: NSRange(location: 999, length: 5),
            in: source
        )

        #expect(range.location + range.length <= source.length)
    }

    @Test func 空の本文でも落ちない() {
        let text = decorated("", selection: NSRange(location: 0, length: 0))

        #expect(text.length == 0)
    }
}
