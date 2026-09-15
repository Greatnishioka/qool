import Foundation

/// 選択した範囲へ文字色を付ける、または外す。
///
/// **Markdown に色の記法はありません。** CommonMark が認める書き方として
/// インライン HTML を使います。他のアプリでも文書としては壊れずに読めますが、
/// **色が出る保証はありません**（HTML を落とす表示系があります）。
nonisolated struct ApplyMarkdownColorUseCase {
    struct Result: Equatable {
        let markdown: String
        let selection: NSRange
    }

    private static let closeTag = "</span>"

    init() {}

    /// - Parameter color: `nil` を渡すと、囲っている指定を外します。
    func callAsFunction(
        _ markdown: String,
        selection: NSRange,
        color: RGBAComponents?
    ) -> Result {
        let source = markdown as NSString
        let range = ToggleInlineMarkdownStyleUseCase.clamped(selection, in: source)

        if let unwrapped = removing(source, range: range) {
            // 外したうえで、新しい色があれば付け直します。
            guard let color else {
                return unwrapped
            }

            return wrapping(unwrapped.markdown as NSString, range: unwrapped.selection, color: color)
        }

        guard let color, range.length > 0 else {
            return Result(markdown: markdown, selection: range)
        }

        return wrapping(source, range: range, color: color)
    }

    private func wrapping(_ source: NSString, range: NSRange, color: RGBAComponents) -> Result {
        let openTag = Self.openTag(for: color)
        let result = NSMutableString(string: source)
        result.insert(Self.closeTag, at: range.location + range.length)
        result.insert(openTag, at: range.location)

        return Result(
            markdown: result as String,
            selection: NSRange(
                location: range.location + (openTag as NSString).length,
                length: range.length
            )
        )
    }

    /// 選択のすぐ外側が `<span ...>` と `</span>` なら外します。
    private func removing(_ source: NSString, range: NSRange) -> Result? {
        let closeLength = (Self.closeTag as NSString).length
        let after = NSRange(location: range.location + range.length, length: closeLength)

        guard after.location + after.length <= source.length,
              source.substring(with: after).lowercased() == Self.closeTag,
              let open = openTagRange(endingAt: range.location, in: source) else {
            return nil
        }

        let result = NSMutableString(string: source)
        result.deleteCharacters(in: after)
        result.deleteCharacters(in: open)

        return Result(
            markdown: result as String,
            selection: NSRange(location: range.location - open.length, length: range.length)
        )
    }

    /// 選択の直前で閉じている開きタグ。**`<` まで戻って形を確かめます。**
    private func openTagRange(endingAt end: Int, in source: NSString) -> NSRange? {
        guard end > 0, source.substring(with: NSRange(location: end - 1, length: 1)) == ">" else {
            return nil
        }

        let head = source.range(
            of: "<span",
            options: [.backwards, .caseInsensitive],
            range: NSRange(location: 0, length: end)
        )

        guard head.location != NSNotFound else {
            return nil
        }

        let tag = NSRange(location: head.location, length: end - head.location)

        // **途中に別のタグを挟んでいたら外しません。** 入れ子を崩します。
        // 末尾の `>` はこのタグ自身のものなので数えません。
        guard !source.substring(with: tag).dropLast().contains(">") else {
            return nil
        }

        return tag
    }

    static func openTag(for color: RGBAComponents) -> String {
        "<span style=\"color:\(hex(color))\">"
    }

    /// **6 桁で書き出します。** 3 桁に縮められる場合もありますが、
    /// 書き出しを 1 つに決めておくと、外すときの照合が単純になります。
    static func hex(_ color: RGBAComponents) -> String {
        let red = Int((color.red * 255).rounded())
        let green = Int((color.green * 255).rounded())
        let blue = Int((color.blue * 255).rounded())

        return String(format: "#%02x%02x%02x", red, green, blue)
    }
}
