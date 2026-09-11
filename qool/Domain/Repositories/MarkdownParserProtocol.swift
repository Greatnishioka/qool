import Foundation

/// 生の Markdown から、意味の付いている範囲を取り出す。
///
/// **Domain は解析器を知りません。** 実装は Infrastructure に置き、
/// ここでは「Markdown を渡すと意味の並びが返る」という契約だけを持ちます。
/// Vision と OpenCV に対して行っているのと同じ分け方です。
nonisolated protocol MarkdownParserProtocol: Sendable {
    /// - Parameter markdown: 生の Markdown。
    /// - Returns: 意味の付いている範囲。**重なります**（太字の中の色など）。
    ///   並びは出てきた順で、同じ範囲に複数の意味が付くことがあります。
    func spans(in markdown: String) -> [RichTextSpan]
}
