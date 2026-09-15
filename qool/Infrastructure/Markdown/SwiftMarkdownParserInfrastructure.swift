import Foundation
import Markdown

/// `swift-markdown` で解析する。
///
/// **位置の単位をここで閉じます。** 解析器は UTF-8 のバイト位置を返し、
/// テキストビューは UTF-16 で数えます。外へ出す `RichTextSpan` は UTF-16 に揃えます。
///
/// **装飾しない記法も受け取ります。** 表やコードブロックは道具から作りませんが、
/// 貼り付けや手入力では入ってきます。意味を付けずに素通しし、原文は一切失いません。
nonisolated struct SwiftMarkdownParserInfrastructure: MarkdownParserProtocol {
    init() {}

    func spans(in markdown: String) -> [RichTextSpan] {
        guard !markdown.isEmpty else {
            return []
        }

        var collector = SpanCollector(
            offsets: MarkdownSourceOffsets(markdown),
            source: markdown as NSString
        )
        collector.collect(Document(parsing: markdown))

        return collector.spans
    }
}

/// 抽象木をたどって範囲を集める。
private nonisolated struct SpanCollector {
    let offsets: MarkdownSourceOffsets
    let source: NSString

    private(set) var spans: [RichTextSpan] = []

    /// - Parameter bound: 親の中身の範囲。**入れ子の強調を切り詰めるために渡します。**
    ///
    ///   `**太字の中の*斜体***` のように、強調が親の末尾で終わると、
    ///   **解析器は斜体の範囲を親の閉じ記号まで伸ばして返します**（実測）。
    ///   そのまま使うと、閉じ記号の `**` まで斜体になります。
    mutating func collect(_ markup: Markup, bound: NSRange? = nil) {
        var content = bound

        if let range = markup.range {
            var nsRange = offsets.range(from: range.lowerBound, to: range.upperBound)

            if let bound {
                nsRange = NSIntersectionRange(nsRange, bound)
            }

            if let kind = Self.kind(of: markup) {
                spans.append(RichTextSpan(range: nsRange, kind: kind))
            }

            content = appendSyntax(of: markup, outer: nsRange)
        }

        collectColors(in: markup)

        for child in markup.children {
            collect(child, bound: content)
        }
    }

    // MARK: - 意味

    private static func kind(of markup: Markup) -> RichTextSpanKind? {
        switch markup {
        case is Strong:
            return .strong
        case is Emphasis:
            return .emphasis
        case is Strikethrough:
            return .strikethrough
        case is InlineCode:
            return .inlineCode
        case let link as Link:
            return .link(destination: link.destination ?? "")
        case let heading as Heading:
            return .heading(level: heading.level)
        case let item as ListItem:
            return .listItem(ordinal: ordinal(of: item), isChecked: item.checkbox.map { $0 == .checked })
        default:
            return nil
        }
    }

    /// 番号付きの項目の番号。**開始番号は `1.` とは限りません。**
    private static func ordinal(of item: ListItem) -> Int? {
        guard let list = item.parent as? OrderedList else {
            return nil
        }

        return Int(list.startIndex) + item.indexInParent
    }

    // MARK: - 記法そのもの

    /// 記法の文字を集める。
    ///
    /// **木は記法の位置を直接教えてくれません。** `Strong` の範囲は `**太字**` 全体で、
    /// 中の `Text` が `太字` を指します。**その差が記法です。**
    /// - Returns: 記法を除いた中身の範囲。子はこの中に収まります。
    @discardableResult
    private mutating func appendSyntax(of markup: Markup, outer: NSRange) -> NSRange {
        if markup is InlineCode {
            appendInlineCodeSyntax(outer: outer)
            return outer
        }

        // **強調の記号は長さが決まっています。** 子との差から出すより確かで、
        // 解析器が返す範囲が伸びていても正しい位置になります。
        if let length = Self.delimiterLength(of: markup), outer.length > length * 2 {
            spans.append(
                RichTextSpan(range: NSRange(location: outer.location, length: length), kind: .syntax)
            )
            spans.append(
                RichTextSpan(
                    range: NSRange(location: outer.location + outer.length - length, length: length),
                    kind: .syntax
                )
            )

            return NSRange(location: outer.location + length, length: outer.length - length * 2)
        }

        guard Self.hasSyntax(markup) else {
            return outer
        }

        let childRanges = markup.children
            .compactMap(\.range)
            .map { offsets.range(from: $0.lowerBound, to: $0.upperBound) }

        guard let first = childRanges.first, let last = childRanges.last else {
            return outer
        }

        // **リストの記号だけは別扱いです。** 隠すと箇条書きに見えなくなります。
        let leadingKind: RichTextSpanKind = markup is ListItem ? .listMarker : .syntax

        if first.location > outer.location {
            spans.append(
                RichTextSpan(
                    range: NSRange(location: outer.location, length: first.location - outer.location),
                    kind: leadingKind
                )
            )
        }

        let outerEnd = outer.location + outer.length
        let lastEnd = last.location + last.length

        if outerEnd > lastEnd {
            spans.append(
                RichTextSpan(
                    range: NSRange(location: lastEnd, length: outerEnd - lastEnd),
                    kind: .syntax
                )
            )
        }

        return NSRange(location: first.location, length: lastEnd - first.location)
    }

    /// 前後に付く記号の長さ。**種類ごとに決まっています**（`**` は 2、`*` は 1）。
    private static func delimiterLength(of markup: Markup) -> Int? {
        switch markup {
        case is Strong, is Strikethrough: return 2
        case is Emphasis: return 1
        default: return nil
        }
    }

    /// 差を記法とみなしてよいもの。
    ///
    /// **段落や文書に当てはめてはいけません。** 子の間にある改行や空行まで
    /// 記法として隠すことになります。
    private static func hasSyntax(_ markup: Markup) -> Bool {
        markup is Link || markup is Heading || markup is ListItem
    }

    /// `` `コード` `` の前後のバッククォート。**子を持たないので差が取れません。**
    private mutating func appendInlineCodeSyntax(outer: NSRange) {
        let text = source.substring(with: outer)
        let leading = text.prefix { $0 == "`" }.count
        let trailing = text.reversed().prefix { $0 == "`" }.count

        guard leading > 0, outer.length > leading + trailing else {
            return
        }

        spans.append(
            RichTextSpan(range: NSRange(location: outer.location, length: leading), kind: .syntax)
        )
        spans.append(
            RichTextSpan(
                range: NSRange(location: outer.location + outer.length - trailing, length: trailing),
                kind: .syntax
            )
        )
    }

    // MARK: - 文字色

    /// 色を集める。
    ///
    /// **開きタグと閉じタグは入れ子になりません。** 段落の兄弟として平らに並ぶので、
    /// 自分で対応付けます。
    ///
    /// **閉じ忘れは段落の終わりまで色が付きます。** 途中で切ると、
    /// 書いている途中の `<span>` が一瞬で消えたり出たりします。
    private mutating func collectColors(in markup: Markup) {
        var open: [(color: RGBAComponents, start: Int)] = []

        for child in markup.children {
            guard let inline = child as? InlineHTML, let range = child.range else {
                continue
            }

            let nsRange = offsets.range(from: range.lowerBound, to: range.upperBound)
            spans.append(RichTextSpan(range: nsRange, kind: .syntax))

            if let color = Self.color(inOpenTag: inline.rawHTML) {
                open.append((color, nsRange.location + nsRange.length))
            } else if Self.isCloseTag(inline.rawHTML), let last = open.popLast() {
                appendColor(last.color, from: last.start, to: nsRange.location)
            }
        }

        guard !open.isEmpty, let range = markup.range else {
            return
        }

        let outer = offsets.range(from: range.lowerBound, to: range.upperBound)

        for last in open {
            appendColor(last.color, from: last.start, to: outer.location + outer.length)
        }
    }

    private mutating func appendColor(_ color: RGBAComponents, from start: Int, to end: Int) {
        guard end > start else {
            return
        }

        spans.append(
            RichTextSpan(range: NSRange(location: start, length: end - start), kind: .color(color))
        )
    }

    /// 受け付けるのは `<span style="color:#RGB">` と `#RRGGBB` だけ。
    ///
    /// **任意の HTML は解釈しません。** 受理する形を狭く固定し、
    /// 外れたものは意味を付けずにそのまま見せます。
    static func color(inOpenTag html: String) -> RGBAComponents? {
        let lowered = html.lowercased()

        guard lowered.hasPrefix("<span"), let colorIndex = lowered.range(of: "color:") else {
            return nil
        }

        let rest = lowered[colorIndex.upperBound...].drop(while: { $0 == " " })

        guard rest.first == "#" else {
            return nil
        }

        let digits = rest.dropFirst().prefix { $0.isHexDigit }

        return hexColor(String(digits))
    }

    static func isCloseTag(_ html: String) -> Bool {
        html.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "</span>"
    }

    private static func hexColor(_ digits: String) -> RGBAComponents? {
        let characters = Array(digits)

        switch characters.count {
        case 3:
            // `#e05` は各桁を 2 度並べた `#ee0055` と同じです。
            return components(characters.map { String(repeating: $0, count: 2) })
        case 6:
            return components(stride(from: 0, to: 6, by: 2).map { String(characters[$0...$0 + 1]) })
        default:
            return nil
        }
    }

    private static func components(_ pairs: [String]) -> RGBAComponents? {
        let values = pairs.compactMap { Int($0, radix: 16) }

        guard values.count == 3 else {
            return nil
        }

        return RGBAComponents(
            red: Double(values[0]) / 255,
            green: Double(values[1]) / 255,
            blue: Double(values[2]) / 255
        )
    }
}
