import Foundation

nonisolated extension NSRange {
    /// 文字列の長さに収めた範囲。
    ///
    /// **範囲外のまま使うと落ちます。** 選択は画面から来るので、
    /// 本文が短くなったあとの古い値が渡ってくることがあります。
    /// 数えるのは **UTF-16** です（`NSRange` がその単位のため）。
    func clamped(toLength length: Int) -> NSRange {
        let location = Swift.min(Swift.max(0, self.location), length)

        return NSRange(
            location: location,
            length: Swift.min(Swift.max(0, self.length), length - location)
        )
    }
}
