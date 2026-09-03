import Combine
import CoreGraphics
import Foundation

@MainActor
final class CanvasViewModel: ObservableObject {
    @Published private(set) var memo: Memo
    @Published var selectedTool: CanvasTool = .select
    @Published var selectedElementIDs: Set<CanvasElement.ID> = []
    @Published var editingUnionElementID: CanvasElement.ID?
    @Published var selectedUnionSourceID: CanvasElementSnapshot.ID?
    @Published var draftElement: CanvasElement?

    private var pathDraftPoints: [CGPoint] = []
    private let selectionService: CanvasSelectionService
    private let draftElementBuilder: CanvasDraftElementBuilder
    private let moveElementsUseCase: MoveCanvasElementsUseCase
    private let deleteElementsUseCase: DeleteCanvasElementsUseCase
    private let updateElementUseCase: UpdateCanvasElementUseCase
    private let unionElementsUseCase: UnionCanvasElementsUseCase
    private let onSave: (Memo) -> Void

    init(
        memo: Memo,
        selectionService: CanvasSelectionService = CanvasSelectionService(),
        draftElementBuilder: CanvasDraftElementBuilder = CanvasDraftElementBuilder(),
        moveElementsUseCase: MoveCanvasElementsUseCase = MoveCanvasElementsUseCase(),
        deleteElementsUseCase: DeleteCanvasElementsUseCase = DeleteCanvasElementsUseCase(),
        updateElementUseCase: UpdateCanvasElementUseCase = UpdateCanvasElementUseCase(),
        unionElementsUseCase: UnionCanvasElementsUseCase = UnionCanvasElementsUseCase(),
        onSave: @escaping (Memo) -> Void
    ) {
        self.memo = memo
        self.selectionService = selectionService
        self.draftElementBuilder = draftElementBuilder
        self.moveElementsUseCase = moveElementsUseCase
        self.deleteElementsUseCase = deleteElementsUseCase
        self.updateElementUseCase = updateElementUseCase
        self.unionElementsUseCase = unionElementsUseCase
        self.onSave = onSave
    }

    var selectedElement: CanvasElement? {
        selectionService.selectedElement(in: memo.canvas.elements, selectedIDs: selectedElementIDs)
    }
    
    var selectedElementID: CanvasElement.ID? {
        selectionService.selectedElementID(from: selectedElementIDs)
    }

    var selectedElementsCount: Int {
        selectedElementIDs.count
    }

    var hasSelection: Bool {
        !selectedElementIDs.isEmpty
    }

    var selectedElements: [CanvasElement] {
        selectionService.selectedElements(in: memo.canvas.elements, selectedIDs: selectedElementIDs)
    }

    var canUnionSelection: Bool {
        selectedElementIDs.count >= 2
    }

    var editingUnionSources: [CanvasElementSnapshot] {
        guard let editingUnionElementID,
              let element = memo.canvas.elements.first(where: { $0.id == editingUnionElementID }) else {
            return []
        }

        return element.unionSourceElements
    }

    var selectedUnionSource: CanvasElementSnapshot? {
        guard let selectedUnionSourceID else {
            return nil
        }

        return editingUnionSources.first { $0.id == selectedUnionSourceID }
    }

    func clearSelection() {
        selectedElementIDs.removeAll()
        editingUnionElementID = nil
        selectedUnionSourceID = nil
    }

    func selectTool(_ tool: CanvasTool) {
        if selectedTool == .path, tool != .path {
            clearPathDraft()
        }

        selectedTool = tool
        if tool != .select {
            clearSelection()
        }
    }

    func placePathPoint(at point: CGPoint, canvasSize: CGSize) {
        guard selectedTool == .path else {
            return
        }

        let point = clamped(point, in: canvasSize)

        // 3点以上ある場合かつ、最初の点の近くに点を置くと、パスを閉じる
        if pathDraftPoints.count >= 3,
           let firstPoint = pathDraftPoints.first,
           distance(from: point, to: firstPoint) <= 18 {
            commitPathDraft()
            return
        }

        pathDraftPoints.append(point)
        draftElement = draftElementBuilder.makePathElement(from: pathDraftPoints, isClosed: false)
    }

    func updateDraft(from start: CGPoint, to current: CGPoint, canvasSize: CGSize) {

        guard selectedTool != .select, selectedTool != .path else {
            return
        }

        let start = clamped(start, in: canvasSize)
        let current = clamped(current, in: canvasSize)
        draftElement = draftElementBuilder.makeElement(for: selectedTool, from: start, to: current)
    }

    func commitDraft(from start: CGPoint, to current: CGPoint, canvasSize: CGSize) {
        updateDraft(from: start, to: current, canvasSize: canvasSize)

        guard let draftElement, draftElementBuilder.isDrawable(draftElement) else {
            self.draftElement = nil
            return
        }

        memo.canvas.elements.append(draftElement)
        selectedTool = .select
        selectedElementIDs = [draftElement.id]
        self.draftElement = nil
        save()
    }

    func selectElement(id: CanvasElement.ID) {
        selectedTool = .select
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        selectedElementIDs = [id]
    }

    func toggleElementSelection(id: CanvasElement.ID) {
        selectedTool = .select
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        if selectedElementIDs.contains(id) {
            selectedElementIDs.remove(id)
        } else {
            selectedElementIDs.insert(id)
        }
    }

    func selectElements(in selectionFrame: CGRect) {
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        selectedElementIDs = selectionService.elementIDs(in: selectionFrame, elements: memo.canvas.elements)
    }

    func elementID(at point: CGPoint) -> CanvasElement.ID? {

        selectionService.elementID(at: point, in: memo.canvas.elements)
    }

    func unionSourceID(at point: CGPoint) -> CanvasElementSnapshot.ID? {
        editingUnionSources.reversed().first { source in
            source.frame.insetBy(dx: -6, dy: -6).contains(point)
        }?.id
    }

    
    func moveSelectedElement(by translation: CGSize, canvasSize: CGSize) {
        guard !selectedElementIDs.isEmpty else {
            return
        }

        let originalFrames = Dictionary(
            uniqueKeysWithValues: memo.canvas.elements
                .filter { selectedElementIDs.contains($0.id) }
                .map { ($0.id, $0.frame) }
        )

        moveElementsUseCase(
            in: &memo.canvas.elements,
            selectedIDs: selectedElementIDs,
            by: translation,
            canvasSize: canvasSize
        )

        for index in memo.canvas.elements.indices where selectedElementIDs.contains(memo.canvas.elements[index].id) {
            let element = memo.canvas.elements[index]
            guard !element.unionSourceElements.isEmpty,
                  let originalFrame = originalFrames[element.id] else {
                continue
            }

            let actualTranslation = CGSize(
                width: element.frame.minX - originalFrame.minX,
                height: element.frame.minY - originalFrame.minY
            )

            memo.canvas.elements[index].unionSourceElements = element.unionSourceElements.map { sourceElement in
                var sourceElement = sourceElement
                sourceElement.frame = sourceElement.frame.offsetBy(
                    dx: actualTranslation.width,
                    dy: actualTranslation.height
                )
                return sourceElement
            }
        }

        save()
    }

    func updateFillColor(_ color: CanvasColor) {
        updateSelectedElement { element in
            element.fillColor = color
        }
    }

    func updateStrokeColor(_ color: CanvasColor) {
        updateSelectedElement { element in
            element.strokeColor = color
        }
    }

    func updateShowsStroke(_ showsStroke: Bool) {
        updateSelectedElement { element in
            element.showsStroke = showsStroke
            if showsStroke, element.strokeWidth == 0 {
                element.strokeWidth = 2
            }
        }
    }

    func updateStrokeWidth(_ strokeWidth: CGFloat) {
        updateSelectedElement { element in
            element.strokeWidth = strokeWidth
            element.showsStroke = strokeWidth > 0
        }
    }

    func updateCornerRadius(_ cornerRadius: CGFloat) {
        updateSelectedElement { element in
            guard element.kind == .rectangle else {
                return
            }

            let maxRadius = max(0, min(element.frame.width, element.frame.height) / 2)
            element.cornerRadius = min(max(cornerRadius, 0), maxRadius)
        }
    }

    func updateText(_ text: String) {
        updateSelectedElement { element in
            element.text = text
        }
    }

    func deleteSelectedElement() {
        guard !selectedElementIDs.isEmpty else {
            return
        }

        deleteElementsUseCase(in: &memo.canvas.elements, selectedIDs: selectedElementIDs)
        selectedElementIDs.removeAll()
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        save()
    }

    func unionSelectedElements() {
        guard canUnionSelection else {
            return
        }

        guard let unionElement = unionElementsUseCase(from: selectedElements) else {
            return
        }

        deleteElementsUseCase(in: &memo.canvas.elements, selectedIDs: selectedElementIDs)
        memo.canvas.elements.append(unionElement)
        selectedElementIDs = [unionElement.id]
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        save()
    }

    func separateSelectedElement() {
        guard let selectedElementID,
              let elementIndex = memo.canvas.elements.firstIndex(where: { $0.id == selectedElementID }) else {
            return
        }

        let sourceElements = memo.canvas.elements[elementIndex].unionSourceElements.map(\.element)
        guard !sourceElements.isEmpty else {
            return
        }

        memo.canvas.elements.remove(at: elementIndex)
        memo.canvas.elements.append(contentsOf: sourceElements)
        selectedElementIDs = Set(sourceElements.map(\.id))
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        save()
    }

    func beginEditingUnionElement(at point: CGPoint) {
        guard selectedTool == .select,
              let elementID = elementID(at: point),
              let element = memo.canvas.elements.first(where: { $0.id == elementID }),
              !element.unionSourceElements.isEmpty else {
            return
        }

        editingUnionElementID = element.id
        selectedElementIDs = [element.id]
        selectedUnionSourceID = unionSourceID(at: point) ?? element.unionSourceElements.last?.id
    }

    func selectUnionSource(id: CanvasElementSnapshot.ID) {
        guard editingUnionSources.contains(where: { $0.id == id }) else {
            return
        }

        selectedUnionSourceID = id
    }

    func moveUnionSource(id: CanvasElementSnapshot.ID, by translation: CGSize, canvasSize: CGSize) {
        guard let editingUnionElementID,
              let elementIndex = memo.canvas.elements.firstIndex(where: { $0.id == editingUnionElementID }),
              let sourceIndex = memo.canvas.elements[elementIndex].unionSourceElements.firstIndex(where: { $0.id == id }) else {
            return
        }

        var sourceElements = memo.canvas.elements[elementIndex].unionSourceElements
        sourceElements[sourceIndex].frame = clamped(
            sourceElements[sourceIndex].frame.offsetBy(dx: translation.width, dy: translation.height),
            in: canvasSize
        )

        let currentUnionElement = memo.canvas.elements[elementIndex]
        guard let updatedUnionElement = unionElementsUseCase(
            from: sourceElements.map(\.element),
            id: currentUnionElement.id,
            styleSource: currentUnionElement
        ) else {
            return
        }

        memo.canvas.elements[elementIndex] = updatedUnionElement
        selectedElementIDs = [updatedUnionElement.id]
        selectedUnionSourceID = id
        save()
    }

    func updateSelectedUnionSourceCornerRadius(_ cornerRadius: CGFloat) {
        guard let selectedUnionSourceID else {
            return
        }

        updateUnionSource(id: selectedUnionSourceID) { sourceElement in
            guard sourceElement.kind == .rectangle else {
                return
            }

            let maxRadius = max(0, min(sourceElement.frame.width, sourceElement.frame.height) / 2)
            sourceElement.cornerRadius = min(max(cornerRadius, 0), maxRadius)
        }
    }

    private func updateSelectedElement(_ mutation: (inout CanvasElement) -> Void) {
        guard let selectedElementID else {
            return
        }

        updateElementUseCase(in: &memo.canvas.elements, id: selectedElementID, mutation)
        save()
    }

    private func updateUnionSource(
        id sourceID: CanvasElementSnapshot.ID,
        mutation: (inout CanvasElementSnapshot) -> Void
    ) {
        guard let editingUnionElementID,
              let elementIndex = memo.canvas.elements.firstIndex(where: { $0.id == editingUnionElementID }),
              let sourceIndex = memo.canvas.elements[elementIndex].unionSourceElements.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        var sourceElements = memo.canvas.elements[elementIndex].unionSourceElements
        mutation(&sourceElements[sourceIndex])

        let currentUnionElement = memo.canvas.elements[elementIndex]
        guard let updatedUnionElement = unionElementsUseCase(
            from: sourceElements.map(\.element),
            id: currentUnionElement.id,
            styleSource: currentUnionElement
        ) else {
            return
        }

        memo.canvas.elements[elementIndex] = updatedUnionElement
        selectedElementIDs = [updatedUnionElement.id]
        selectedUnionSourceID = sourceID
        save()
    }

    private func save() {
        onSave(memo)
    }

    private func commitPathDraft() {
        // パスが3点以下の場合はドラフトをクリアして終了する。
        guard let pathElement = draftElementBuilder.makePathElement(from: pathDraftPoints, isClosed: true),
              pathElement.pathPoints.count >= 3 else {
            clearPathDraft()
            return
        }

        memo.canvas.elements.append(pathElement)
        selectedTool = .select
        selectedElementIDs = [pathElement.id]
        clearPathDraft()
        save()
    }

    private func clearPathDraft() {
        pathDraftPoints = []
        draftElement = nil
    }

    private func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), size.width),
            y: min(max(point.y, 0), size.height)
        )
    }

    private func clamped(_ frame: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: min(max(frame.minX, 0), max(0, size.width - frame.width)),
            y: min(max(frame.minY, 0), max(0, size.height - frame.height)),
            width: frame.width,
            height: frame.height
        )
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
