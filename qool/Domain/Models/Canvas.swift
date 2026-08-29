nonisolated struct Canvas: Equatable, Hashable, Codable {
    var elements: [CanvasElement]

    init(elements: [CanvasElement] = []) {
        self.elements = elements
    }
}
