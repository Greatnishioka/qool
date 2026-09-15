import Foundation

/// 選択した範囲に付け外しできる、前後を同じ記号で囲む書式。
///
/// **囲む記号が前後で同じものだけを集めています。** リンクと色は形が違うので、
/// 別のユースケースが扱います（[#21](https://github.com/Greatnishioka/qool/issues/21)）。
nonisolated enum InlineMarkdownStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case strong
    case emphasis
    case strikethrough
    case inlineCode

    var id: String { rawValue }

    var delimiter: String {
        switch self {
        case .strong: return "**"
        case .emphasis: return "*"
        case .strikethrough: return "~~"
        case .inlineCode: return "`"
        }
    }

    /// 選択の両側に並んでいる記号の数から、この書式が付いているかを見る。
    ///
    /// **数を見ないと `*` と `**` を取り違えます。** `**太字**` の外側は
    /// 「`*` が 2 つ」なので、素朴に 1 文字ずつ比べると斜体が付いていることになり、
    /// 斜体を足したいのに太字が外れます。
    ///
    /// ```
    /// *   1 つ → 斜体
    /// **  2 つ → 太字
    /// *** 3 つ → 太字と斜体
    /// ```
    func isApplied(runLength: Int) -> Bool {
        switch self {
        case .strong, .strikethrough:
            return runLength >= 2
        case .emphasis:
            return runLength == 1 || runLength >= 3
        case .inlineCode:
            return runLength >= 1
        }
    }
}
