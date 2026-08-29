import CoreGraphics

nonisolated struct MoveCanvasElementsUseCase {
    private let updateElements: UpdateCanvasElementsUseCase
    private let selectionService: CanvasSelectionService

    init(
        updateElements: UpdateCanvasElementsUseCase = UpdateCanvasElementsUseCase(),
        selectionService: CanvasSelectionService = CanvasSelectionService()
    ) {
        self.updateElements = updateElements
        self.selectionService = selectionService
    }

    func callAsFunction(
        in elements: inout [CanvasElement],
        selectedIDs: Set<CanvasElement.ID>,
        by translation: CGSize,
        canvasSize: CGSize
    ) {
        guard !selectedIDs.isEmpty else {
            return
        }

        updateElements(&elements, selectedIDs: selectedIDs) { element in
            element.frame = element.frame.offsetBy(dx: translation.width, dy: translation.height)
        }

        guard let selectedFrame = selectionService.selectedElementsFrame(
            in: elements,
            selectedIDs: selectedIDs
        ) else {
            return
        }

        let canvasFrame = CGRect(origin: .zero, size: canvasSize)
        guard !canvasFrame.contains(selectedFrame) else {
            return
        }

        let clampedFrame = clamped(selectedFrame, in: canvasSize)
        let correction = CGSize(
            width: clampedFrame.minX - selectedFrame.minX,
            height: clampedFrame.minY - selectedFrame.minY
        )

        updateElements(&elements, selectedIDs: selectedIDs) { element in
            element.frame = element.frame.offsetBy(dx: correction.width, dy: correction.height)
        }
    }

    private func clamped(_ frame: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: min(max(frame.minX, 0), max(0, size.width - frame.width)),
            y: min(max(frame.minY, 0), max(0, size.height - frame.height)),
            width: frame.width,
            height: frame.height
        )
    }
}
