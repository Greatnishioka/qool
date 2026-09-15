import Foundation

/// 記法を切らない選択へ正す。
///
/// **書式を付ける前に必ず通します。** そうしないと `<span ...>` や `**` の途中で
/// 切れた範囲を囲むことになり、**本文が壊れます。**
///
/// [MarkdownSelectionGuard](../../../Domain/Services/MarkdownSelectionGuard.swift) は
/// **隠れている**記法しか避けません。カーソルのあるブロックでは記法が見えていて、
/// 消せるように選べる必要があるためです。**書式を付けるときはそれでは足りません。**
/// 見えているものも含めて、記法はすべて避けます。
nonisolated enum MarkdownSyntaxBoundary {
    /// - Returns: 正した選択。**選んだ範囲が記法の中だけだったときは `nil`。**
    ///   そこに書式を付けられる文字はないので、呼び出し側は何もしません。
    static func selection(
        _ selection: NSRange,
        in markdown: String,
        parser: any MarkdownParserProtocol,
        guard selectionGuard: MarkdownSelectionGuard
    ) -> NSRange? {
        let length = (markdown as NSString).length
        let syntax = parser.spans(in: markdown)
            .filter { $0.kind == .syntax }
            .map(\.range)

        let corrected = selectionGuard.selection(
            selection,
            movingFrom: selection,
            avoiding: syntax,
            length: length
        )

        // **切り詰めたあとの長さで見ます。** 範囲外の選択は「記法しか選んでいない」
        // のではなく「何も選んでいない」ので、書式は付けられます。
        guard selection.clamped(toLength: length).length == 0 || corrected.length > 0 else {
            return nil
        }

        return corrected
    }
}
