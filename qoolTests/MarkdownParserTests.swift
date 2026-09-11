import Foundation
import Testing
@testable import qool

/// 生の Markdown から意味の範囲を取り出す処理の検証。
///
/// **位置の単位が一番危ないところです。** 解析器は UTF-8 のバイト数で数え、
/// `NSTextView` は UTF-16 で数えます。日本語や絵文字を混ぜて固定します。
///
/// **`#expect` の中では複雑な式を書きません。** 値は先に取り出します。
struct MarkdownParserTests {
    private let parser = SwiftMarkdownParserInfrastructure()

    /// 指定した意味が付いている範囲を、その文字列に直して返します。
    private func texts(_ markdown: String, _ matches: (RichTextSpanKind) -> Bool) -> [String] {
        let source = markdown as NSString

        return parser.spans(in: markdown)
            .filter { matches($0.kind) }
            .map { source.substring(with: $0.range) }
    }

    private func strongTexts(_ markdown: String) -> [String] {
        texts(markdown) { $0 == .strong }
    }

    private func syntaxTexts(_ markdown: String) -> [String] {
        texts(markdown) { $0 == .syntax }
    }

    // MARK: - 位置の単位

    /// **これが崩れると日本語で装飾がずれます。**
    /// 解析器は「あ」を 3 と数え、テキストビューは 1 と数えます。
    @Test func 日本語を挟んでも範囲がずれない() {
        let strong = strongTexts("あいうえお**太字**かきくけこ")

        #expect(strong == ["**太字**"])
    }

    /// 絵文字は UTF-16 でも 1 ではありません。
    @Test func 絵文字を挟んでも範囲がずれない() {
        let strong = strongTexts("a👨‍👩‍👧b**太字**c")

        #expect(strong == ["**太字**"])
    }

    @Test func 複数行でも範囲がずれない() {
        let markdown = """
        あいうえお
        かきくけこ**太字**さしすせそ
        """

        #expect(strongTexts(markdown) == ["**太字**"])
    }

    @Test func 改行コードがCRLFでも範囲がずれない() {
        let markdown = "あいうえお\r\nかきくけこ**太字**さしすせそ"

        #expect(strongTexts(markdown) == ["**太字**"])
    }

    // MARK: - インライン

    @Test func 斜体と打ち消しとコードを見つける() {
        let emphasis = texts("*斜体*") { $0 == .emphasis }
        let strikethrough = texts("~~消し~~") { $0 == .strikethrough }
        let code = texts("`コード`") { $0 == .inlineCode }

        #expect(emphasis == ["*斜体*"])
        #expect(strikethrough == ["~~消し~~"])
        #expect(code == ["`コード`"])
    }

    @Test func リンクは行き先を持つ() {
        let spans = parser.spans(in: "[ここ](https://example.com)")
        let destinations = spans.compactMap { span -> String? in
            guard case let .link(destination) = span.kind else {
                return nil
            }

            return destination
        }

        #expect(destinations == ["https://example.com"])
    }

    @Test func 入れ子の強調をどちらも見つける() {
        let markdown = "**太字の中の*斜体***"
        let strong = strongTexts(markdown)
        let emphasis = texts(markdown) { $0 == .emphasis }

        #expect(strong == ["**太字の中の*斜体***"])
        #expect(emphasis == ["*斜体*"])
    }

    // MARK: - 記法そのもの

    /// **記法の位置は木が直接教えてくれません。** 外側と中身の差から出しています。
    @Test func 太字の記号だけを記法として取り出す() {
        let syntax = syntaxTexts("あ**太字**い")

        #expect(syntax == ["**", "**"])
    }

    @Test func 見出しの記号を記法として取り出す() {
        let syntax = syntaxTexts("## 見出し")

        #expect(syntax == ["## "])
    }

    @Test func コードのバッククォートを記法として取り出す() {
        let syntax = syntaxTexts("`コード`")

        #expect(syntax == ["`", "`"])
    }

    @Test func リンクの記号を記法として取り出す() {
        let syntax = syntaxTexts("[ここ](https://example.com)")

        #expect(syntax == ["[", "](https://example.com)"])
    }

    // MARK: - 見出しとリスト

    @Test func 見出しの深さを持つ() {
        let levels = parser.spans(in: "### みだし").compactMap { span -> Int? in
            guard case let .heading(level) = span.kind else {
                return nil
            }

            return level
        }

        #expect(levels == [3])
    }

    @Test func 箇条書きは番号を持たない() {
        let items = listItems("- ひとつ\n- ふたつ")

        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.ordinal == nil })
    }

    /// **開始番号は 1 とは限りません。**
    @Test func 番号付きは開始番号から数える() {
        let items = listItems("3. みっつ\n4. よっつ")
        let ordinals = items.map(\.ordinal)

        #expect(ordinals == [3, 4])
    }

    @Test func チェックボックスの状態を持つ() {
        let items = listItems("- [ ] まだ\n- [x] すんだ")
        let checked = items.map(\.isChecked)

        #expect(checked == [false, true])
    }

    private func listItems(_ markdown: String) -> [(ordinal: Int?, isChecked: Bool?)] {
        parser.spans(in: markdown).compactMap { span in
            guard case let .listItem(ordinal, isChecked) = span.kind else {
                return nil
            }

            return (ordinal, isChecked)
        }
    }

    // MARK: - 文字色

    private func colorTexts(_ markdown: String) -> [String] {
        texts(markdown) { kind in
            guard case .color = kind else {
                return false
            }

            return true
        }
    }

    private func colors(_ markdown: String) -> [RGBAComponents] {
        parser.spans(in: markdown).compactMap { span in
            guard case let .color(components) = span.kind else {
                return nil
            }

            return components
        }
    }

    /// **開きタグと閉じタグは入れ子で返ってきません。** 自分で対応付けています。
    @Test func 囲まれた範囲に色が付く() {
        let markdown = "ふつう<span style=\"color:#ff0000\">あか</span>ふつう"

        #expect(colorTexts(markdown) == ["あか"])
    }

    @Test func 三桁の指定も六桁と同じに読む() {
        let short = colors("<span style=\"color:#e05\">あ</span>")
        let long = colors("<span style=\"color:#ee0055\">あ</span>")

        #expect(short == long)
    }

    @Test func 色の成分を読み取る() {
        let components = colors("<span style=\"color:#ff8000\">あ</span>")
        let first = components.first

        #expect(first?.red == 1)
        #expect(first?.blue == 0)
    }

    @Test func 大文字の指定も読む() {
        let upper = colors("<SPAN STYLE=\"COLOR:#FF0000\">あ</SPAN>")

        #expect(upper.count == 1)
    }

    /// **閉じ忘れは段落の終わりまで色が付きます。** 途中で切ると、
    /// 書いている最中の `<span>` が出たり消えたりします。
    @Test func 閉じ忘れは段落の終わりまで色が付く() {
        let markdown = "まえ<span style=\"color:#ff0000\">あとぜんぶ"

        #expect(colorTexts(markdown) == ["あとぜんぶ"])
    }

    @Test func 色の中の太字も見つかる() {
        let markdown = "<span style=\"color:#ff0000\">あか**ふとい**</span>"

        #expect(strongTexts(markdown) == ["**ふとい**"])
        #expect(colorTexts(markdown) == ["あか**ふとい**"])
    }

    /// **受け付ける形は狭く固定しています。** 外れたものに意味は付けません。
    @Test func 色以外の指定には意味を付けない() {
        let markdown = "<span style=\"font-weight:bold\">あ</span>"

        #expect(colorTexts(markdown).isEmpty)
    }

    @Test func タグそのものは記法として扱う() {
        let markdown = "<span style=\"color:#ff0000\">あ</span>"
        let syntax = syntaxTexts(markdown)

        #expect(syntax == ["<span style=\"color:#ff0000\">", "</span>"])
    }

    // MARK: - 対応していない記法

    /// **原文は一切失いません。** 意味を付けないだけです。
    @Test func 表には意味を付けないが本文は残る() {
        let markdown = "| あ | い |\n|---|---|\n| 1 | 2 |"
        let spans = parser.spans(in: markdown)
        let hasStrong = spans.contains { $0.kind == .strong }

        #expect(!hasStrong)
    }

    @Test func 空の本文では何も返さない() {
        #expect(parser.spans(in: "").isEmpty)
    }

    @Test func 書きかけの記法では意味を付けない() {
        #expect(strongTexts("**かきかけ").isEmpty)
    }
}
