import Foundation
import Testing
@testable import qool

/// 隠れている記法へキャレットと選択が入らないことの検証。
///
/// **記法の文字は消えていません。** 幅を潰して見えなくしているだけなので、
/// 放っておくと見えないタグが選択に入り、書式を付けたときに本文が壊れます。
struct MarkdownSelectionGuardTests {
    private let guardian = MarkdownSelectionGuard()

    /// `あ**太字**い` を想定します。`**` は 1〜3 と 6〜8。
    private let hidden = [
        NSRange(location: 1, length: 2),
        NSRange(location: 6, length: 2)
    ]
    private let length = 10

    private func selection(_ proposed: NSRange, from previous: NSRange) -> NSRange {
        guardian.selection(proposed, movingFrom: previous, avoiding: hidden, length: length)
    }

    private func caret(_ location: Int, from previous: Int) -> Int {
        selection(
            NSRange(location: location, length: 0),
            from: NSRange(location: previous, length: 0)
        ).location
    }

    // MARK: - キャレット

    /// 右へ動いているなら、記法の後ろへ抜けます。
    @Test func 右へ動くと記法を飛び越える() {
        #expect(caret(2, from: 1) == 3)
    }

    /// 左へ動いているなら、記法の手前へ抜けます。
    @Test func 左へ動くと記法の手前へ戻る() {
        #expect(caret(2, from: 3) == 1)
    }

    @Test func 記法の外なら動かさない() {
        #expect(caret(4, from: 3) == 4)
        #expect(caret(0, from: 1) == 0)
    }

    /// **端は含みません。** ちょうど手前や直後は、切っていないので許します。
    @Test func 記法の端には止まれる() {
        #expect(caret(1, from: 0) == 1)
        #expect(caret(3, from: 4) == 3)
    }

    // MARK: - 範囲

    /// **広げずに縮めます。** 広げるとタグごと囲むことになり、
    /// 新しいタグが古いタグを巻き込んで入れ子になります。
    @Test func 記法を切る選択は内側へ縮む() {
        let result = selection(NSRange(location: 2, length: 5), from: NSRange(location: 2, length: 0))

        // 2 は `**` の途中なので 3 へ、7 も途中なので 6 へ。
        #expect(result == NSRange(location: 3, length: 3))
    }

    @Test func 記法をまるごと含む選択はそのまま() {
        let result = selection(NSRange(location: 1, length: 7), from: NSRange(location: 1, length: 0))

        #expect(result == NSRange(location: 1, length: 7))
    }

    @Test func 縮めて空になればキャレットにする() {
        // `**` の中だけを選んだ場合。
        let result = selection(NSRange(location: 1, length: 1), from: NSRange(location: 1, length: 0))

        #expect(result.length == 0)
    }

    @Test func 隠れている記法がなければ何もしない() {
        let result = guardian.selection(
            NSRange(location: 2, length: 5),
            movingFrom: NSRange(location: 0, length: 0),
            avoiding: [],
            length: length
        )

        #expect(result == NSRange(location: 2, length: 5))
    }

    @Test func 範囲外でも落ちない() {
        let result = guardian.selection(
            NSRange(location: 999, length: 999),
            movingFrom: NSRange(location: 0, length: 0),
            avoiding: hidden,
            length: length
        )

        #expect(result.location + result.length <= length)
    }

    // MARK: - 削除

    /// **片方だけ消えると記法が壊れます。** `**太字**` の後ろで 1 文字消すと
    /// `**太字*` になり、太字でもなくなったうえに記号だけ残ります。
    @Test func 記法にかかる削除は記法ごと広がる() {
        let result = guardian.deletion(NSRange(location: 7, length: 1), avoiding: hidden)

        #expect(result == NSRange(location: 6, length: 2))
    }

    @Test func 記法にかからない削除は変えない() {
        let result = guardian.deletion(NSRange(location: 4, length: 1), avoiding: hidden)

        #expect(result == NSRange(location: 4, length: 1))
    }

    @Test func 両側の記法にかかれば両方を含める() {
        let result = guardian.deletion(NSRange(location: 2, length: 5), avoiding: hidden)

        #expect(result == NSRange(location: 1, length: 7))
    }
}
