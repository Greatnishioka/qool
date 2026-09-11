import Foundation

/// 外から来た文字列を、編集中のテキストビューへ流し込んでよいかを決める。
///
/// **判断をビューから出しています。** テキストビューは実機でしか動かせないので、
/// 差し替えの可否と選択の付け直しだけを取り出して、テストで固定できるようにしました。
nonisolated struct MarkdownEditingSync {
    init() {}

    /// 流し込んでよいか。
    ///
    /// **変換中は決して差し替えません。** 差し替えると入力中の変換が中断され、
    /// 打った文字が消えます。同じ内容のときも触りません。触ると選択が飛びます。
    func shouldApply(external: String, current: String, isComposing: Bool) -> Bool {
        guard !isComposing else {
            return false
        }

        return external != current
    }

    /// 差し替えたあとに戻す選択範囲。
    ///
    /// **短くなっていれば切り詰めます。** そのまま戻すと範囲外になり、
    /// `NSTextView` が例外を投げます。
    func preservedSelection(_ selection: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, selection.location), length)

        return NSRange(location: location, length: min(selection.length, length - location))
    }
}
