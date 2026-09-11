import Foundation
import Testing
@testable import qool

/// 外から来た文字列を編集中のテキストビューへ流し込む判断の検証。
///
/// **テキストビューは実機でしか動かせません。** 判断だけを取り出したので、
/// ここで固定できるのは「いつ触るか」と「選択をどう戻すか」です。
struct MarkdownEditingSyncTests {
    private let sync = MarkdownEditingSync()

    // MARK: - 流し込んでよいか

    /// **変換中は決して差し替えません。** 差し替えると打っている途中の変換が消えます。
    @Test func 変換中は流し込まない() {
        #expect(!sync.shouldApply(external: "あたらしい", current: "ふるい", isComposing: true))
    }

    /// 同じ内容で触ると選択が飛びます。
    @Test func 内容が同じなら流し込まない() {
        #expect(!sync.shouldApply(external: "おなじ", current: "おなじ", isComposing: false))
    }

    @Test func 変換していなくて内容が違えば流し込む() {
        #expect(sync.shouldApply(external: "あたらしい", current: "ふるい", isComposing: false))
    }

    // MARK: - 選択の戻し方

    @Test func 入る範囲ならそのまま戻す() {
        let preserved = sync.preservedSelection(NSRange(location: 2, length: 3), in: "0123456789")

        #expect(preserved.location == 2)
        #expect(preserved.length == 3)
    }

    /// **短くなっていれば切り詰めます。** 範囲外のまま戻すと `NSTextView` が落ちます。
    @Test func 文字列が短くなったら切り詰める() {
        let preserved = sync.preservedSelection(NSRange(location: 8, length: 4), in: "012")

        #expect(preserved.location == 3)
        #expect(preserved.length == 0)
    }

    @Test func 末尾にかかる選択は入る分だけ残す() {
        let preserved = sync.preservedSelection(NSRange(location: 1, length: 9), in: "012")

        #expect(preserved.location == 1)
        #expect(preserved.length == 2)
    }

    /// **UTF-16 で数えます。** `NSRange` がそうなので、絵文字を含む文字列で
    /// 文字数と食い違います。ここを取り違えると、日本語や絵文字で範囲外になります。
    @Test func 絵文字を含んでもUTF16で数える() {
        let text = "a👨‍👩‍👧b"
        let length = (text as NSString).length
        let preserved = sync.preservedSelection(NSRange(location: 0, length: 999), in: text)

        #expect(length == 10)
        #expect(text.count == 3)
        #expect(preserved.length == length)
    }
}
