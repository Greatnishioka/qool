import CoreGraphics
import Foundation

nonisolated struct CanvasEditingUseCases {
    init() {}

    func moveElements(
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

        guard let selectedFrame = selectedElementsFrame(in: elements, selectedIDs: selectedIDs) else {
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

    func deleteElements(in elements: inout [CanvasElement], selectedIDs: Set<CanvasElement.ID>) {
        elements.removeAll { selectedIDs.contains($0.id) }
    }

    func updateElement(
        in elements: inout [CanvasElement],
        id: CanvasElement.ID,
        _ mutation: (inout CanvasElement) -> Void
    ) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutation(&elements[index])
    }

    func updateElements(
        _ elements: inout [CanvasElement],
        selectedIDs: Set<CanvasElement.ID>,
        _ mutation: (inout CanvasElement) -> Void
    ) {
        for index in elements.indices where selectedIDs.contains(elements[index].id) {
            mutation(&elements[index])
        }
    }

    private func selectedElementsFrame(
        in elements: [CanvasElement],
        selectedIDs: Set<CanvasElement.ID>
    ) -> CGRect? {
        let frames = elements
            .filter { selectedIDs.contains($0.id) }
            .map(\.frame)

        guard let firstFrame = frames.first else {
            return nil
        }

        return frames.dropFirst().reduce(firstFrame) { partialResult, frame in
            partialResult.union(frame)
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
