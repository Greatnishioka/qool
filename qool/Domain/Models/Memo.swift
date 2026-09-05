import CoreGraphics
import Foundation

nonisolated struct Memo: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    var title: String
    var updatedAt: Date
    var canvas: Canvas
    /// デスクトップに貼ったフローティングウィンドウの左下位置（画面座標）。
    /// **`nil` は「貼っていない」を表します。** 貼っているかどうかを別のフラグで持つと、
    /// 位置だけ残った状態と食い違います。
    var floatingOrigin: CGPoint?

    init(
        id: UUID = UUID(),
        title: String,
        updatedAt: Date = Date(),
        canvas: Canvas = Canvas(),
        floatingOrigin: CGPoint? = nil
    ) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.canvas = canvas
        self.floatingOrigin = floatingOrigin
    }
}
