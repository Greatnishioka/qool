import Foundation
import Markdown

/// 解析器が返す位置を、テキストビューが数える位置へ直す表。
///
/// **`swift-markdown` の `SourceLocation` は行と、行頭からの UTF-8 バイト数です。**
/// `NSTextView` の `NSRange` は UTF-16 で数えます。**定数倍ではありません。**
///
/// ```
/// "あい"          UTF-8  6 バイト / UTF-16 2
/// "a👨‍👩‍👧b"        UTF-8 20 バイト / UTF-16 10
/// ```
///
/// ここを素通しすると、**日本語を打った瞬間に装飾の位置がずれます。**
nonisolated struct MarkdownSourceOffsets {
    /// 行頭の UTF-8 バイト位置。`SourceLocation.line` は 1 から数えます。
    private let lineStarts: [Int]
    /// UTF-8 のバイト位置に対する UTF-16 の位置。**バイトの数だけ持ちます。**
    /// 走るたびに数え直すと、1 文字打つごとに本文を 2 度なめることになります。
    private let utf16Offsets: [Int]

    let utf16Length: Int

    init(_ text: String) {
        var lineStarts = [0]
        var utf16Offsets: [Int] = []
        utf16Offsets.reserveCapacity(text.utf8.count + 1)

        var utf16 = 0
        var byte = 0

        for scalar in text.unicodeScalars {
            let width = Self.utf8Width(of: scalar)

            for _ in 0..<width {
                utf16Offsets.append(utf16)
            }

            utf16 += scalar.value > 0xFFFF ? 2 : 1
            byte += width

            if scalar == "\n" {
                lineStarts.append(byte)
            }
        }

        utf16Offsets.append(utf16)

        self.lineStarts = lineStarts
        self.utf16Offsets = utf16Offsets
        utf16Length = utf16
    }

    func utf16Offset(for location: SourceLocation) -> Int {
        let line = location.line - 1

        guard line >= 0, line < lineStarts.count else {
            return utf16Length
        }

        let byte = lineStarts[line] + (location.column - 1)

        guard byte >= 0, byte < utf16Offsets.count else {
            return utf16Length
        }

        return utf16Offsets[byte]
    }

    /// 始点と終点から範囲を作る。**終点は含みません。**
    func range(from start: SourceLocation, to end: SourceLocation) -> NSRange {
        let lower = utf16Offset(for: start)
        let upper = utf16Offset(for: end)

        return NSRange(location: min(lower, upper), length: abs(upper - lower))
    }

    /// **符号化の幅は値から出します。** `String(scalar).utf8.count` だと
    /// 文字ごとに文字列を作ることになり、本文の長さに比例して確保が増えます。
    private static func utf8Width(of scalar: Unicode.Scalar) -> Int {
        switch scalar.value {
        case ..<0x80: return 1
        case ..<0x800: return 2
        case ..<0x1_0000: return 3
        default: return 4
        }
    }
}
