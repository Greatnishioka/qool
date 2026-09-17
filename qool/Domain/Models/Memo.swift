import CoreGraphics
import Foundation

/// 付箋の雛形。**形とレイアウトを持ちます。**
///
/// **机の上の 1 枚は [StickyNote](StickyNote.swift) です。** 以前はこの型が両方を兼ね、
/// 貼れるのは 1 枚だけでした（[#29](https://github.com/Greatnishioka/qool/issues/29)）。
nonisolated struct Memo: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    var title: String
    var updatedAt: Date
    var canvas: Canvas

    init(
        id: UUID = UUID(),
        title: String,
        updatedAt: Date = Date(),
        canvas: Canvas = Canvas()
    ) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.canvas = canvas
    }
}
