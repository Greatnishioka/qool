import Foundation

/// 本文のどこに、どんな意味が付いているか。
///
/// **範囲は生の Markdown の上の位置です。** 記法を除いた文字列ではありません
/// （[#21](https://github.com/Greatnishioka/qool/issues/21) の不変条件）。
/// 表示用の位置へ変換する必要がないので、選択やキャレットとそのまま突き合わせられます。
nonisolated struct RichTextSpan: Equatable, Hashable {
    /// 範囲。**UTF-16 で数えます。**
    ///
    /// `NSTextView` の `NSRange` がこの単位だからです。
    /// 解析器が返すのは UTF-8 のバイト位置なので、変換は Infrastructure で閉じます。
    let range: NSRange
    let kind: RichTextSpanKind

    init(range: NSRange, kind: RichTextSpanKind) {
        self.range = range
        self.kind = kind
    }
}
