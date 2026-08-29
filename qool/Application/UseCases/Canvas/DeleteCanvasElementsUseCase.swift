nonisolated struct DeleteCanvasElementsUseCase {
    init() {}

    func callAsFunction(in elements: inout [CanvasElement], selectedIDs: Set<CanvasElement.ID>) {
        elements.removeAll { selectedIDs.contains($0.id) }
    }
}
