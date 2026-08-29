nonisolated struct CanvasPathContour: Equatable, Hashable, Codable {
    var points: [NormalizedPoint]
    var isClosed: Bool

    init(points: [NormalizedPoint], isClosed: Bool = true) {
        self.points = points
        self.isClosed = isClosed
    }
}
