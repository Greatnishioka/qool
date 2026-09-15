import Foundation

/// 隠れている記法の中へ、キャレットと選択が入らないようにする。
///
/// **記法の文字は消えていません。幅を潰して見えなくしているだけ**です
/// （[#21](https://github.com/Greatnishioka/qool/issues/21) の不変条件。
/// 生の Markdown を抱えたままにするため、文字列からは取り除けません）。
///
/// そのままにすると、見えている文字を選んだつもりでも**見えないタグが選択に入り**、
/// 書式を付けたときに**タグの途中で切れて本文が壊れます。**
///
/// **見えている記法は避けません。** カーソルのあるブロックでは `**` が見えていて、
/// 消せないと困るためです。避けるのは「隠れているもの」だけです。
nonisolated struct MarkdownSelectionGuard {
    init() {}

    /// 記法の中に端が落ちない選択。
    ///
    /// - Parameter previous: 直前の選択。**動いている向きを知るために要ります。**
    ///   右へ動いているなら記法の後ろへ、左へ動いているなら手前へ飛ばします。
    /// - Parameter hidden: 隠れている記法の範囲。重なっていない前提です。
    func selection(
        _ proposed: NSRange,
        movingFrom previous: NSRange,
        avoiding hidden: [NSRange],
        length: Int
    ) -> NSRange {
        let range = Self.clamped(proposed, length: length)

        guard !hidden.isEmpty else {
            return range
        }

        guard range.length > 0 else {
            return NSRange(
                location: caret(range.location, movingFrom: previous.location, avoiding: hidden),
                length: 0
            )
        }

        // **範囲は縮めます。** 広げるとタグごと囲むことになり、
        // 新しいタグが古いタグを巻き込んで入れ子になります。
        let start = boundary(range.location, avoiding: hidden, movingForward: true)
        let end = boundary(range.location + range.length, avoiding: hidden, movingForward: false)

        guard end > start else {
            return NSRange(location: start, length: 0)
        }

        return NSRange(location: start, length: end - start)
    }

    /// 記法をまたぐ削除を、記法ごと消す範囲へ広げる。
    ///
    /// **片方だけ消えると記法が壊れます。** `**太字**` の後ろで 1 文字消すと
    /// `**太字*` になり、太字でもなくなったうえに記号だけ残ります。
    func deletion(_ proposed: NSRange, avoiding hidden: [NSRange]) -> NSRange {
        var result = proposed

        for range in hidden where NSIntersectionRange(range, result).length > 0 {
            result = NSUnionRange(result, range)
        }

        return result
    }

    // MARK: -

    /// キャレットの落とし所。**通り抜ける向きへ飛ばします。**
    private func caret(_ location: Int, movingFrom previous: Int, avoiding hidden: [NSRange]) -> Int {
        guard let range = hidden.first(where: { Self.isInside(location, $0) }) else {
            return location
        }

        return previous <= range.location ? range.location + range.length : range.location
    }

    /// 範囲の端の落とし所。**外側ではなく内側へ寄せます。**
    private func boundary(_ location: Int, avoiding hidden: [NSRange], movingForward: Bool) -> Int {
        guard let range = hidden.first(where: { Self.isInside(location, $0) }) else {
            return location
        }

        return movingForward ? range.location + range.length : range.location
    }

    /// **端は含みません。** 記法のちょうど手前や直後は、切っていないので許します。
    private static func isInside(_ location: Int, _ range: NSRange) -> Bool {
        location > range.location && location < range.location + range.length
    }

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)

        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }
}
