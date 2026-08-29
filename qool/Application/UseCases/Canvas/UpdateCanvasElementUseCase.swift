nonisolated struct UpdateCanvasElementUseCase {
    init() {}

    func callAsFunction(
        in elements: inout [CanvasElement],
        id: CanvasElement.ID,
        _ mutation: (inout CanvasElement) -> Void
    ) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutation(&elements[index])
    }
}
