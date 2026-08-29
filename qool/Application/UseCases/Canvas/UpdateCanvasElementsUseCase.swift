nonisolated struct UpdateCanvasElementsUseCase {
    init() {}

    func callAsFunction(
        _ elements: inout [CanvasElement],
        selectedIDs: Set<CanvasElement.ID>,
        _ mutation: (inout CanvasElement) -> Void
    ) {
        for index in elements.indices where selectedIDs.contains(elements[index].id) {
            mutation(&elements[index])
        }
    }
}
