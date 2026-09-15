import AppKit
import Foundation
import Testing
@testable import qool

/// 改行を挟んだ本文の検証。
///
/// **表示だけの状態は正しく扱えています。** 編集中に記法を見せる単位が
/// 改行で切られている件は [#23](https://github.com/Greatnishioka/qool/issues/23) に回しました。
struct MarkdownNewlineTests {
    private let builder = MarkdownAttributedTextBuilder()
    private let parser = SwiftMarkdownParserInfrastructure()
    private let style = RichTextStyle(baseFont: .systemFont(ofSize: 20), baseColor: .black)

    private func text(_ markdown: String) -> NSAttributedString {
        builder.attributedString(markdown: markdown, selection: nil, style: style)
    }

    private func font(_ t: NSAttributedString, at index: Int) -> NSFont? {
        t.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    private func isBold(_ markdown: String, _ needle: String) -> Bool {
        let index = (markdown as NSString).range(of: needle).location
        return font(text(markdown), at: index)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
    }

    @Test func 二行目の太字() {
        #expect(isBold("いちぎょうめ\n**ふとじ**", "ふとじ"))
    }

    @Test func 空行を挟んだ二段落目の太字() {
        #expect(isBold("いちぎょうめ\n\n**ふとじ**", "ふとじ"))
    }

    @Test func 見出しの次の行の太字() {
        #expect(isBold("# みだし\n**ふとじ**", "ふとじ"))
    }

    @Test func 一行目の太字_二行目あり() {
        #expect(isBold("**ふとじ**\nにぎょうめ", "ふとじ"))
    }

    @Test func 改行をまたぐ色() {
        let markdown = "<span style=\"color:#ff0000\">あか\nつづき</span>"
        let index = (markdown as NSString).range(of: "つづき").location
        let color = text(markdown).attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor

        #expect((color?.usingColorSpace(.sRGB)?.redComponent ?? 0) > 0.9)
    }

    @Test func 改行の次の行の記法が潰れる() {
        let markdown = "いち\n**ふとじ**"
        let index = (markdown as NSString).range(of: "**").location

        #expect((font(text(markdown), at: index)?.pointSize ?? 99) < 1)
    }

    @Test func 箇条書きが二行とも項目になる() {
        let markdown = "- ひとつ\n- ふたつ"
        let items = parser.spans(in: markdown).filter { span in
            if case .listItem = span.kind { return true }
            return false
        }

        #expect(items.count == 2)
    }

    // MARK: - 編集中

    private func editing(_ markdown: String, caretAt needle: String) -> NSAttributedString {
        let location = (markdown as NSString).range(of: needle).location

        return builder.attributedString(
            markdown: markdown,
            selection: NSRange(location: location, length: 0),
            style: style
        )
    }

    /// **箇条書きは項目まで降ります。** リスト全体を単位にすると、
    /// 1 つ直すだけで `- ` が一斉に現れて読めなくなります。
    @Test func 箇条書きは項目ごとに記法が出る() {
        let markdown = "- ひとつ\n- ふたつ"
        let t = editing(markdown, caretAt: "ひとつ")
        let first = font(t, at: 0)?.pointSize ?? 0
        let secondIndex = (markdown as NSString).range(of: "- ふたつ").location
        let second = font(t, at: secondIndex)?.pointSize ?? 99

        #expect(first > 1)
        #expect(second < 1)
    }

    @Test func 改行を挟んでも本文は変わらない() {
        let markdown = "いち\n**に**\n\nさん"

        #expect(text(markdown).string == markdown)
    }
}
