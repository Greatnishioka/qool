import Foundation

/// 選択した範囲の書式を付け外しする。
///
/// **生の Markdown の文字列を書き換えるだけです。** 表示の属性は触りません。
/// 保存する正が Markdown 1 本なので、書式の操作もそこへ寄せられます
/// （[#21](https://github.com/Greatnishioka/qool/issues/21)）。
nonisolated struct ToggleInlineMarkdownStyleUseCase {
    struct Result: Equatable {
        let markdown: String
        /// 書き換えたあとの選択。**囲った中身を選んだままにします。**
        /// 記号まで選ばれていると、続けて別の書式を付けたときに二重に囲まれます。
        let selection: NSRange
    }

    init() {}

    func callAsFunction(
        _ markdown: String,
        selection: NSRange,
        style: InlineMarkdownStyle
    ) -> Result {
        let source = markdown as NSString
        let delimiter = style.delimiter
        let length = (delimiter as NSString).length
        let range = Self.content(Self.clamped(selection, in: source), delimiter: delimiter, in: source)

        let marker = (delimiter as NSString).character(at: 0)
        let run = min(
            Self.runLengthBefore(marker, at: range.location, in: source),
            Self.runLengthAfter(marker, at: range.location + range.length, in: source)
        )

        guard style.isApplied(runLength: run) else {
            let result = NSMutableString(string: source)
            result.insert(delimiter, at: range.location + range.length)
            result.insert(delimiter, at: range.location)

            return Result(
                markdown: result as String,
                selection: NSRange(location: range.location + length, length: range.length)
            )
        }

        let result = NSMutableString(string: source)
        // **後ろから消します。** 前を先に消すと、後ろの位置がずれます。
        result.deleteCharacters(in: NSRange(location: range.location + range.length, length: length))
        result.deleteCharacters(in: NSRange(location: range.location - length, length: length))

        return Result(
            markdown: result as String,
            selection: NSRange(location: range.location - length, length: range.length)
        )
    }

    /// 記法の文字を除いた中身の範囲。
    ///
    /// **記号ごと選んで押されることがあります。** その場合も、中身だけを選んだときと
    /// 同じ答えになるように、先に絞ってから考えます。
    private static func content(_ range: NSRange, delimiter: String, in source: NSString) -> NSRange {
        let length = (delimiter as NSString).length

        guard range.length >= length * 2,
              source.substring(with: NSRange(location: range.location, length: length)) == delimiter,
              source.substring(
                  with: NSRange(location: range.location + range.length - length, length: length)
              ) == delimiter else {
            return range
        }

        return NSRange(location: range.location + length, length: range.length - length * 2)
    }

    /// 手前に並んでいる同じ文字の数。
    private static func runLengthBefore(_ marker: unichar, at end: Int, in source: NSString) -> Int {
        var count = 0
        var index = end - 1

        while index >= 0, source.character(at: index) == marker {
            count += 1
            index -= 1
        }

        return count
    }

    /// 後ろに並んでいる同じ文字の数。
    private static func runLengthAfter(_ marker: unichar, at start: Int, in source: NSString) -> Int {
        var count = 0
        var index = start

        while index < source.length, source.character(at: index) == marker {
            count += 1
            index += 1
        }

        return count
    }

    static func clamped(_ range: NSRange, in source: NSString) -> NSRange {
        let location = min(max(0, range.location), source.length)

        return NSRange(location: location, length: min(range.length, source.length - location))
    }
}
