import AppKit

/// 装飾を当てた結果。
///
/// **隠した記法の場所も一緒に返します。** キャレットと選択をそこへ入れないために、
/// テキストビューが持ち続ける必要があります
/// （[#21](https://github.com/Greatnishioka/qool/issues/21)）。
nonisolated struct MarkdownDecoration {
    /// 生の Markdown と**一字一句同じ文字列**に、属性だけを載せたもの。
    let text: NSAttributedString
    /// 幅を潰して見えなくした記法の範囲。
    let hiddenSyntaxRanges: [NSRange]
}
