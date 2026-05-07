import Combine
import CoreGraphics
import Foundation

@MainActor
final class CanvasViewModel: ObservableObject {
    @Published private(set) var memo: Memo
    @Published var selectedTool: CanvasTool = .select
    // 選択されている要素の ID の Set ( JS の Set と同様)。複数選択をサポートするために Set で管理する。
    @Published var selectedElementIDs: Set<CanvasElement.ID> = []
    @Published var draftElement: CanvasElement?

    private var pathDraftPoints: [CGPoint] = []
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
        guard selectedElementIDs.count == 1,
              let selectedElementID = selectedElementIDs.first else {
            return nil
        }

        // filter みたいな感じ。
        // ここでは、selectedElementID に対応する要素を見つけて最初の一つを返す。
        return memo.canvas.elements.first { $0.id == selectedElementID }
    }
    
    // 選択されている要素。
    // 複数選択時は nil を返す。
    var selectedElementID: CanvasElement.ID? {
        guard selectedElementIDs.count == 1 else {
            return nil
        }

        return selectedElementIDs.first
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

        // 選択中のIDに対応する要素のフレームを取得し、それらを結合して一つのフレームを作成する。
        let frames = memo.canvas.elements
            .filter { selectedElementIDs.contains($0.id) }
            .map(\.frame)

        // いまだに書き方に慣れないが、frames.first を取り出して、それが nil であれば nil を返す。そうでなければ、frames の残りのフレームと結合して一つのフレームを作成して返す。
        guard let firstFrame = frames.first else {
            return nil
        }

        return frames.dropFirst().reduce(firstFrame) { partialResult, frame in
            partialResult.union(frame)
        }
    }

    // 選択されている要素の配列。キャンバスないから探し、複数選択をサポートするために配列で返す。
    var selectedElements: [CanvasElement] {
        memo.canvas.elements.filter { selectedElementIDs.contains($0.id) }
    }

    // 選択をクリアする関数。全部削除。
    func clearSelection() {
        selectedElementIDs.removeAll()
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
        draftElement = makePathElement(from: pathDraftPoints, isClosed: false)
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
        selectedElementIDs = [draftElement.id]
        self.draftElement = nil
        save()
    }

    // 要素を選択する関数。指定されたIDの要素を選択状態にする。
    func selectElement(id: CanvasElement.ID) {
        selectedTool = .select
        selectedElementIDs = [id]
    }

    func selectElements(in selectionFrame: CGRect) {
        let selectedIDs = memo.canvas.elements
            .filter { element in
                selectionFrame.intersects(hitFrame(for: element))
            }
            .map(\.id)

        selectedElementIDs = Set(selectedIDs)
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
        // 追加した要素を選択状態にする。
        selectedElementIDs = [element.id]
        save()
    }

    func moveSelectedElement(by translation: CGSize, canvasSize: CGSize) {
        guard !selectedElementIDs.isEmpty else {
            return
        }

        updateSelectedElements { element in
            element.frame = element.frame.offsetBy(dx: translation.width, dy: translation.height)
        }

        if let selectedElementsFrame, !CGRect(origin: .zero, size: canvasSize).contains(selectedElementsFrame) {
            let clampedFrame = clamped(selectedElementsFrame, in: canvasSize)
            let correction = CGSize(
                width: clampedFrame.minX - selectedElementsFrame.minX,
                height: clampedFrame.minY - selectedElementsFrame.minY
            )
            updateSelectedElements { element in
                element.frame = element.frame.offsetBy(dx: correction.width, dy: correction.height)
            }
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
        guard !selectedElementIDs.isEmpty else {
            return
        }

        memo.canvas.elements.removeAll { selectedElementIDs.contains($0.id) }
        selectedElementIDs.removeAll()
        save()
    }

    private func updateSelectedElement(_ mutation: (inout CanvasElement) -> Void) {
        guard let selectedElementID else {
            return
        }

        updateElement(id: selectedElementID, mutation)
    }

    // 複数選択されている要素すべてに対して、同じ変更を適用する関数。
    private func updateSelectedElements(_ mutation: (inout CanvasElement) -> Void) {
        let ids = selectedElementIDs
        guard !ids.isEmpty else {
            return
        }

        for index in memo.canvas.elements.indices where ids.contains(memo.canvas.elements[index].id) {
            mutation(&memo.canvas.elements[index])
        }
        save()
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

            // 選択ツールと、曲線ツールが選ばれている場合、要素は作成しない。
        case .select, .path:
            return nil
        case .rectangle:
            return CanvasElement(
                kind: .rectangle,
                frame: normalizedFrame(from: start, to: current, minimumSize: CGSize(width: 1, height: 1)),
                fillColor: .paper
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

    // 最終的にパスを確定し、キャンバスに描画する関数。
    private func commitPathDraft() {

        // パスが3点以下の場合はドラフトをクリアして終了する。
        guard let pathElement = makePathElement(from: pathDraftPoints, isClosed: true),
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

    // 点の配列からパス要素を作成する関数。点の配列と、パスが閉じているかどうかを引数に取り、CanvasElement を返す。
    private func makePathElement(from points: [CGPoint], isClosed: Bool) -> CanvasElement? {
        guard let firstPoint = points.first else {
            return nil
        }

        let bounds = points.dropFirst().reduce(CGRect(origin: firstPoint, size: .zero)) { partialResult, point in
            partialResult.union(CGRect(origin: point, size: .zero))
        }
        let frame = bounds.insetBy(dx: -8, dy: -8)
        let safeFrame = CGRect(
            x: frame.minX,
            y: frame.minY,
            width: max(frame.width, 16),
            height: max(frame.height, 16)
        )
        let pathPoints = points.map { point in
            NormalizedPoint(
                x: Double((point.x - safeFrame.minX) / safeFrame.width),
                y: Double((point.y - safeFrame.minY) / safeFrame.height)
            )
        }

        return CanvasElement(
            kind: .path,
            frame: safeFrame,
            fillColor: .sky,
            strokeColor: .ink,
            strokeWidth: 2,
            showsStroke: true,
            pathPoints: pathPoints,
            isClosedPath: isClosed
        )
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

    // 距離計算関数。三角形の定理で斜辺を計算するイメージ。
    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
