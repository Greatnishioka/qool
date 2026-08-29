import CoreGraphics
import Foundation

nonisolated struct CanvasSelectionService {
    init() {}

    func selectedElement(
        in elements: [CanvasElement],
        selectedIDs: Set<CanvasElement.ID>
    ) -> CanvasElement? {
        guard selectedIDs.count == 1,
              let selectedID = selectedIDs.first else {
            return nil
        }

        return elements.first { $0.id == selectedID }
    }

    func selectedElementID(from selectedIDs: Set<CanvasElement.ID>) -> CanvasElement.ID? {
        guard selectedIDs.count == 1 else {
            return nil
        }

        return selectedIDs.first
    }

    func selectedElements(
        in elements: [CanvasElement],
        selectedIDs: Set<CanvasElement.ID>
    ) -> [CanvasElement] {
        elements.filter { selectedIDs.contains($0.id) }
    }

    func selectedElementsFrame(
        in elements: [CanvasElement],
        selectedIDs: Set<CanvasElement.ID>
    ) -> CGRect? {
        let frames = selectedElements(in: elements, selectedIDs: selectedIDs).map(\.frame)
        guard let firstFrame = frames.first else {
            return nil
        }

        return frames.dropFirst().reduce(firstFrame) { partialResult, frame in
            partialResult.union(frame)
        }
    }

    func elementID(at point: CGPoint, in elements: [CanvasElement]) -> CanvasElement.ID? {
        elements.reversed().first { element in
            hitFrame(for: element).contains(point)
        }?.id
    }

    func elementIDs(in selectionFrame: CGRect, elements: [CanvasElement]) -> Set<CanvasElement.ID> {
        Set(
            elements
                .filter { element in
                    selectionFrame.intersects(hitFrame(for: element))
                }
                .map(\.id)
        )
    }

    func hitFrame(for element: CanvasElement) -> CGRect {
        let inset: CGFloat = element.kind == .line ? -16 : -4
        return element.frame.insetBy(dx: inset, dy: inset)
    }
}
