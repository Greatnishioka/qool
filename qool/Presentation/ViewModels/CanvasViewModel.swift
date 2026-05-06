import Combine
import CoreGraphics
import Foundation

@MainActor
final class CanvasViewModel: ObservableObject {
    @Published private(set) var memo: Memo
    @Published var selectedTool: CanvasTool = .select
    @Published var selectedElementID: CanvasElement.ID?
    @Published var draftElement: CanvasElement?

    private let elementFactory: CanvasElementFactory
    private let onSave: (Memo) -> Void

    init(
        memo: Memo,
        elementFactory: CanvasElementFactory,
        onSave: @escaping (Memo) -> Void
    ) {
        self.memo = memo
        self.elementFactory = elementFactory
        self.onSave = onSave
    }

    var selectedElement: CanvasElement? {
        guard let selectedElementID else {
            return nil
        }

        // filter みたいな感じ。
        // ここでは、selectedElementID に対応する要素を見つけて最初の一つを返す。
        return memo.canvas.elements.first { $0.id == selectedElementID }
    }

    // 選択をクリアする関数。選択された要素がなくなる。
    func clearSelection() {
        selectedElementID = nil
    }

    // ツールを選択する関数。選択ツール以外が選ばれた場合、選択状態をクリアする。
    func selectTool(_ tool: CanvasTool) {
        selectedTool = tool
        if tool != .select {
            clearSelection()
        }
    }

    // ドラッグ中に使用する関数。ドラッグの開始点から現在の位置までの間で、ドラフト要素を更新する。
    func updateDraft(from start: CGPoint, to current: CGPoint, canvasSize: CGSize) {

        // 選択ツールが選ばれている場合、ドラフト要素は作成しない。
        guard selectedTool != .select else {
            return
        }

        // ドラフト要素を作成するために、開始点と現在の位置をキャンバスのサイズ内にクランプする。
        // まぁつまりは、ドラッグがキャンバスの外に出ないようにするための処理。
        let start = clamped(start, in: canvasSize)
        let current = clamped(current, in: canvasSize)
        draftElement = makeElement(for: selectedTool, from: start, to: current)
    }

    func commitDraft(from start: CGPoint, to current: CGPoint, canvasSize: CGSize) {
        updateDraft(from: start, to: current, canvasSize: canvasSize)

        // ドラフト要素が存在し、かつ描画可能な状態であることを確認する。
        guard let draftElement, isDrawable(draftElement) else {
            self.draftElement = nil
            return
        }

        // ドラフト要素をキャンバスに追加し、選択ツールに切り替えて、その要素を選択状態にする。
        memo.canvas.elements.append(draftElement)
        selectedTool = .select
        selectedElementID = draftElement.id
        self.draftElement = nil
        save()
    }

    // 要素を選択する関数。指定されたIDの要素を選択状態にする。
    func selectElement(id: CanvasElement.ID) {
        selectedTool = .select
        selectedElementID = id
    }

    // 指定された点にある要素のIDを返す関数。
    func elementID(at point: CGPoint) -> CanvasElement.ID? {

        // 要素の配列を逆順にして、点が要素のヒットフレーム内にある最初の要素を見つける。
        memo.canvas.elements.reversed().first { element in
            hitFrame(for: element).contains(point)
        }?.id
    }

    
    func addElement(using tool: CanvasTool, at point: CGPoint) {
        guard let element = elementFactory.makeElement(for: tool, at: point) else {
            return
        }

        memo.canvas.elements.append(element)
        selectedTool = .select
        selectedElementID = element.id
        save()
    }

    func moveSelectedElement(by translation: CGSize, canvasSize: CGSize) {
        guard let selectedElementID else {
            return
        }

        updateElement(id: selectedElementID) { element in
            let proposed = element.frame.offsetBy(dx: translation.width, dy: translation.height)
            element.frame = clamped(proposed, in: canvasSize)
        }
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
        guard let selectedElementID else {
            return
        }

        memo.canvas.elements.removeAll { $0.id == selectedElementID }
        self.selectedElementID = nil
        save()
    }

    private func updateSelectedElement(_ mutation: (inout CanvasElement) -> Void) {
        guard let selectedElementID else {
            return
        }

        updateElement(id: selectedElementID, mutation)
    }

    private func updateElement(id: CanvasElement.ID, _ mutation: (inout CanvasElement) -> Void) {
        guard let index = memo.canvas.elements.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutation(&memo.canvas.elements[index])
        save()
    }

    private func save() {
        onSave(memo)
    }

    private func makeElement(for tool: CanvasTool, from start: CGPoint, to current: CGPoint) -> CanvasElement? {
        switch tool {
        case .select:
            return nil
        case .rectangle:
            return CanvasElement(
                kind: .rectangle,
                frame: normalizedFrame(from: start, to: current, minimumSize: CGSize(width: 1, height: 1)),
                fillColor: .paper
            )
        case .path:
            return CanvasElement(
                kind: .path,
                frame: normalizedFrame(from: start, to: current, minimumSize: CGSize(width: 1, height: 1)),
                fillColor: .sky
            )
        case .line:
            let dx = current.x - start.x
            let dy = current.y - start.y
            let length = max(1, hypot(dx, dy))
            let center = CGPoint(x: start.x + dx / 2, y: start.y + dy / 2)
            let angle = atan2(dy, dx) * 180 / .pi

            return CanvasElement(
                kind: .line,
                frame: CGRect(x: center.x - length / 2, y: center.y - 14, width: length, height: 28),
                fillColor: .clear,
                strokeWidth: 4,
                rotationAngleDegrees: angle
            )
        case .text:
            return CanvasElement(
                kind: .text,
                frame: normalizedFrame(from: start, to: current, minimumSize: CGSize(width: 1, height: 1)),
                fillColor: .clear,
                strokeWidth: 0,
                showsStroke: false,
                text: "テキスト"
            )
        case .image:
            return CanvasElement(
                kind: .imageCutout,
                frame: normalizedFrame(from: start, to: current, minimumSize: CGSize(width: 1, height: 1)),
                fillColor: .coral
            )
        }
    }

    private func normalizedFrame(from start: CGPoint, to current: CGPoint, minimumSize: CGSize) -> CGRect {
        let minX = min(start.x, current.x)
        let minY = min(start.y, current.y)
        let width = max(abs(current.x - start.x), minimumSize.width)
        let height = max(abs(current.y - start.y), minimumSize.height)

        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private func isDrawable(_ element: CanvasElement) -> Bool {
        switch element.kind {
        case .line:
            element.frame.width >= 8
        case .rectangle, .path, .text, .imageCutout:
            element.frame.width >= 8 && element.frame.height >= 8
        }
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

    private func hitFrame(for element: CanvasElement) -> CGRect {
        let inset: CGFloat = element.kind == .line ? -16 : -4
        return element.frame.insetBy(dx: inset, dy: inset)
    }
}
