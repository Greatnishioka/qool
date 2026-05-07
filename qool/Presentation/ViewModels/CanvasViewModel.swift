import Combine
import CoreGraphics
import Foundation

@MainActor
final class CanvasViewModel: ObservableObject {
    @Published private(set) var memo: Memo
    @Published var selectedTool: CanvasTool = .select
    // 選択されている要素の ID の Set ( JS の Set と同様)。複数選択をサポートするために Set で管理する。
    @Published var selectedElementIDs: Set<CanvasElement.ID> = []
    @Published var editingUnionElementID: CanvasElement.ID?
    @Published var selectedUnionSourceID: CanvasElementSnapshot.ID?
    @Published var draftElement: CanvasElement?

    private var pathDraftPoints: [CGPoint] = []
    private let elementFactory: CanvasElementFactory
    private let selectionService: CanvasSelectionService
    private let draftElementBuilder: CanvasDraftElementBuilder
    private let editingUseCases: CanvasEditingUseCases
    private let unionUseCase: CanvasUnionUseCase
    private let onSave: (Memo) -> Void

    init(
        memo: Memo,
        elementFactory: CanvasElementFactory,
        selectionService: CanvasSelectionService = CanvasSelectionService(),
        draftElementBuilder: CanvasDraftElementBuilder = CanvasDraftElementBuilder(),
        editingUseCases: CanvasEditingUseCases = CanvasEditingUseCases(),
        unionUseCase: CanvasUnionUseCase = CanvasUnionUseCase(),
        onSave: @escaping (Memo) -> Void
    ) {
        self.memo = memo
        self.elementFactory = elementFactory
        self.selectionService = selectionService
        self.draftElementBuilder = draftElementBuilder
        self.editingUseCases = editingUseCases
        self.unionUseCase = unionUseCase
        self.onSave = onSave
    }

    var selectedElement: CanvasElement? {
        selectionService.selectedElement(in: memo.canvas.elements, selectedIDs: selectedElementIDs)
    }
    
    // 選択されている要素。
    // 複数選択時は nil を返す。
    var selectedElementID: CanvasElement.ID? {
        selectionService.selectedElementID(from: selectedElementIDs)
    }

    // 選択されている要素のカウント。
    var selectedElementsCount: Int {
        selectedElementIDs.count
    }

    // 要素が選択されているかどうか。
    var hasSelection: Bool {
        !selectedElementIDs.isEmpty
    }

    // 洗濯用の枠を表示するために、選択されている要素のフレームを計算する。
    var selectedElementsFrame: CGRect? {
        selectionService.selectedElementsFrame(in: memo.canvas.elements, selectedIDs: selectedElementIDs)
    }

    // 選択されている要素の配列。キャンバスないから探し、複数選択をサポートするために配列で返す。
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

    // 選択をクリアする関数。全部削除。
    func clearSelection() {
        selectedElementIDs.removeAll()
        editingUnionElementID = nil
        selectedUnionSourceID = nil
    }

    // ツールを選択する関数。選択ツール以外が選ばれた場合、選択状態をクリアする。
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

    // ドラッグ中に使用する関数。ドラッグの開始点から現在の位置までの間で、ドラフト要素を更新する。
    func updateDraft(from start: CGPoint, to current: CGPoint, canvasSize: CGSize) {

        // 選択ツールと、曲線ツールが選ばれている場合、ドラフト要素は作成しない。
        guard selectedTool != .select, selectedTool != .path else {
            return
        }

        // ドラフト要素を作成するために、開始点と現在の位置をキャンバスのサイズ内にクランプする。
        // まぁつまりは、ドラッグがキャンバスの外に出ないようにするための処理。
        let start = clamped(start, in: canvasSize)
        let current = clamped(current, in: canvasSize)
        draftElement = draftElementBuilder.makeElement(for: selectedTool, from: start, to: current)
    }

    func commitDraft(from start: CGPoint, to current: CGPoint, canvasSize: CGSize) {
        updateDraft(from: start, to: current, canvasSize: canvasSize)

        // ドラフト要素が存在し、かつ描画可能な状態であることを確認する。
        guard let draftElement, draftElementBuilder.isDrawable(draftElement) else {
            self.draftElement = nil
            return
        }

        // ドラフト要素をキャンバスに追加し、選択ツールに切り替えて、その要素を選択状態にする。
        memo.canvas.elements.append(draftElement)
        selectedTool = .select
        selectedElementIDs = [draftElement.id]
        self.draftElement = nil
        save()
    }

    // 要素を選択する関数。指定されたIDの要素を選択状態にする。
    func selectElement(id: CanvasElement.ID) {
        selectedTool = .select
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        selectedElementIDs = [id]
    }

    func selectElements(in selectionFrame: CGRect) {
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        selectedElementIDs = selectionService.elementIDs(in: selectionFrame, elements: memo.canvas.elements)
    }

    // 指定された点にある要素のIDを返す関数。
    func elementID(at point: CGPoint) -> CanvasElement.ID? {

        selectionService.elementID(at: point, in: memo.canvas.elements)
    }

    func unionSourceID(at point: CGPoint) -> CanvasElementSnapshot.ID? {
        editingUnionSources.reversed().first { source in
            source.frame.insetBy(dx: -6, dy: -6).contains(point)
        }?.id
    }

    
    func addElement(using tool: CanvasTool, at point: CGPoint) {
        guard let element = elementFactory.makeElement(for: tool, at: point) else {
            return
        }

        memo.canvas.elements.append(element)
        selectedTool = .select
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        // 追加した要素を選択状態にする。
        selectedElementIDs = [element.id]
        save()
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

        editingUseCases.moveElements(
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

    func updateText(_ text: String) {
        updateSelectedElement { element in
            element.text = text
        }
    }

    func deleteSelectedElement() {
        guard !selectedElementIDs.isEmpty else {
            return
        }

        editingUseCases.deleteElements(in: &memo.canvas.elements, selectedIDs: selectedElementIDs)
        selectedElementIDs.removeAll()
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        save()
    }

    // 選択されている要素を結合する関数。複数選択されている要素を一つの要素にまとめる。
    func unionSelectedElements() {
        guard canUnionSelection else {
            return
        }

        guard let unionElement = unionUseCase.unionElement(from: selectedElements) else {
            return
        }

        editingUseCases.deleteElements(in: &memo.canvas.elements, selectedIDs: selectedElementIDs)
        memo.canvas.elements.append(unionElement)
        selectedElementIDs = [unionElement.id]
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
        guard let updatedUnionElement = unionUseCase.unionElement(
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

    private func updateSelectedElement(_ mutation: (inout CanvasElement) -> Void) {
        guard let selectedElementID else {
            return
        }

        editingUseCases.updateElement(in: &memo.canvas.elements, id: selectedElementID, mutation)
        save()
    }

    private func save() {
        onSave(memo)
    }

    // 最終的にパスを確定し、キャンバスに描画する関数。
    private func commitPathDraft() {

        // パスが3点以下の場合はドラフトをクリアして終了する。
        guard let pathElement = draftElementBuilder.makePathElement(from: pathDraftPoints, isClosed: true),
              pathElement.pathPoints.count >= 3 else {
            clearPathDraft()
            return
        }

        memo.canvas.elements.append(pathElement)
        selectedTool = .select
        // 追加した要素を選択状態にする。
        selectedElementIDs = [pathElement.id]
        clearPathDraft()
        save()
    }

    // パスのドラフトをクリアする関数。ドラフト用の点の配列とドラフト要素をリセットする。
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

    // 距離計算関数。三角形の定理で斜辺を計算するイメージ。
    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
