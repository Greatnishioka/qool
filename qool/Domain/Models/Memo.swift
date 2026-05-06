import Foundation

struct Memo: Identifiable, Equatable, Hashable {
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
