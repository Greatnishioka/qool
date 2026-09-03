import AppKit
import SwiftUI

struct CanvasSurface: View {
    /// ドラッグの判定に使うしきい値。
    private enum Threshold {
        /// これ以下の移動はドラッグではなくクリックとして扱う。
        static let tapSlop: CGFloat = 4
        /// これ以下は動いていないものとみなし、保存を走らせない。
        static let moveEpsilon: CGFloat = 0.5
        /// 範囲選択として成立する最小の大きさ。
        static let marqueeMinimum: CGFloat = 4
    }

    @ObservedObject var viewModel: CanvasViewModel

    private var elements: [CanvasElement] { viewModel.memo.canvas.elements }
    private var draftElement: CanvasElement? { viewModel.draftElement }
    private var selectedElementIDs: Set<CanvasElement.ID> { viewModel.selectedElementIDs }
    private var unionSourceElements: [CanvasElementSnapshot] { viewModel.editingUnionSources }
    private var selectedUnionSourceID: CanvasElementSnapshot.ID? { viewModel.selectedUnionSourceID }
    private var selectedTool: CanvasTool { viewModel.selectedTool }

    @State private var dragTarget: CanvasDragTarget = .none

    /// ドラッグ中だけの表示上のずれ。**ジェスチャ終了時に自動で戻ります。**
    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                canvasBackground
                    .gesture(canvasGesture(in: proxy.size))
                    .simultaneousGesture(doubleClickGesture)

                elementLayer
                unionSourceLayer
                marqueeLayer
                draftLayer
            }
            .clipShape(Rectangle())
        }
    }

    // MARK: - レイヤー

    private var canvasBackground: some View {
        Rectangle()
            .fill(Color.white)
            .overlay {
                GridPattern()
                    .stroke(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 0.5)
            }
            .contentShape(Rectangle())
    }

    /// 要素は描画だけを担い、入力は背景の 1 つのジェスチャが受け取ります。
    private var elementLayer: some View {
        ForEach(elements) { element in
            CanvasElementView(
                element: element,
                isSelected: selectedElementIDs.contains(element.id)
            )
            .offset(dragOffset(for: element.id))
            .allowsHitTesting(false)
        }
    }

    private var unionSourceLayer: some View {
        ForEach(unionSourceElements) { sourceElement in
            CanvasElementView(
                element: sourceElement.element,
                isSelected: selectedUnionSourceID == sourceElement.id
            )
            .opacity(selectedUnionSourceID == sourceElement.id ? 0.62 : 0.34)
            .offset(unionSourceOffset(for: sourceElement.id))
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var marqueeLayer: some View {
        if case let .marquee(start, current) = dragTarget {
            SelectionMarquee(frame: normalizedFrame(from: start, to: current))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var draftLayer: some View {
        if let draftElement {
            CanvasElementView(element: draftElement, isSelected: true)
                .opacity(0.72)
                .allowsHitTesting(false)
        }
    }

    // MARK: - 入力

    /// 結合要素の中身を編集に入る操作。
    ///
    /// 自前で時間と距離から判定していたものを標準ジェスチャに寄せました。
    /// **システムのダブルクリック間隔設定に従うようになります**（以前は 0.35 秒固定）。
    /// ドラッグと同時に認識させるのは、1 回目・2 回目のクリックが持つ
    /// 選択の挙動をそのまま残すためです。
    private var doubleClickGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                viewModel.beginEditingUnionElement(at: value.location)
            }
    }

    private func canvasGesture(in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragTranslation) { value, translation, _ in
                translation = value.translation
            }
            .onChanged { handleDragChanged($0, in: canvasSize) }
            .onEnded { handleDragEnded($0, in: canvasSize) }
    }

    private func handleDragChanged(_ value: DragGesture.Value, in canvasSize: CGSize) {
        guard selectedTool == .select else {
            guard selectedTool != .path else {
                return
            }

            viewModel.updateDraft(from: value.startLocation, to: value.location, canvasSize: canvasSize)
            return
        }

        // 対象はドラッグ開始時に一度だけ決め、以降は変えません。
        // 途中で決め直すと、動かしている最中に掴む要素が入れ替わります。
        if case .none = dragTarget {
            dragTarget = makeDragTarget(at: value.startLocation, current: value.location)
        }

        if case let .marquee(start, _) = dragTarget {
            dragTarget = .marquee(start: start, current: value.location)
        }
    }

    private func makeDragTarget(at startLocation: CGPoint, current: CGPoint) -> CanvasDragTarget {
        if let hitUnionSourceID = viewModel.unionSourceID(at: startLocation) {
            viewModel.selectUnionSource(id: hitUnionSourceID)
            return .unionSource(hitUnionSourceID)
        }

        guard let hitElementID = viewModel.elementID(at: startLocation) else {
            return .marquee(start: startLocation, current: current)
        }

        if isShiftSelectionActive {
            return .toggling(hitElementID)
        }

        if selectedElementIDs.contains(hitElementID) {
            return .elements(selectedElementIDs)
        }

        viewModel.selectElement(id: hitElementID)
        return .elements([hitElementID])
    }

    private func handleDragEnded(_ value: DragGesture.Value, in canvasSize: CGSize) {
        guard selectedTool == .select else {
            guard selectedTool != .path else {
                if isTap(value) {
                    viewModel.placePathPoint(at: value.location, canvasSize: canvasSize)
                }
                return
            }

            viewModel.commitDraft(from: value.startLocation, to: value.location, canvasSize: canvasSize)
            return
        }

        defer { dragTarget = .none }

        switch dragTarget {
        case let .toggling(elementID):
            if isTap(value) {
                viewModel.toggleElementSelection(id: elementID)
            }

        case let .unionSource(sourceID):
            viewModel.selectUnionSource(id: sourceID)
            if hasMoved(value) {
                viewModel.moveUnionSource(id: sourceID, by: value.translation, canvasSize: canvasSize)
            }

        case let .elements(elementIDs):
            if hasMoved(value) {
                viewModel.moveSelectedElement(by: value.translation, canvasSize: canvasSize)
            } else {
                if elementIDs.count == 1, let elementID = elementIDs.first {
                    viewModel.selectElement(id: elementID)
                }
            }

        case let .marquee(start, _):
            let selectionFrame = normalizedFrame(from: start, to: value.location)
            if selectionFrame.width >= Threshold.marqueeMinimum
                || selectionFrame.height >= Threshold.marqueeMinimum {
                viewModel.selectElements(in: selectionFrame)
            } else {
                viewModel.clearSelection()
            }

        case .none:
            viewModel.clearSelection()
        }
    }

    private func dragOffset(for elementID: CanvasElement.ID) -> CGSize {
        guard case let .elements(elementIDs) = dragTarget, elementIDs.contains(elementID) else {
            return .zero
        }

        return dragTranslation
    }

    private func unionSourceOffset(for sourceID: CanvasElementSnapshot.ID) -> CGSize {
        guard case let .unionSource(activeSourceID) = dragTarget, activeSourceID == sourceID else {
            return .zero
        }

        return dragTranslation
    }

    /// 動いていないとみなす範囲。クリックとドラッグを分けます。
    private func isTap(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) <= Threshold.tapSlop
            && abs(value.translation.height) <= Threshold.tapSlop
    }

    private func hasMoved(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > Threshold.moveEpsilon
            || abs(value.translation.height) > Threshold.moveEpsilon
    }

    /// macOS では修飾キーの現在値をいつでも読めるため、状態を持ちません。
    /// iOS では `UIPress` を拾うために専用の responder が要りました。
    private var isShiftSelectionActive: Bool {
        NSEvent.modifierFlags.contains(.shift)
    }

    private func normalizedFrame(from start: CGPoint, to current: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

}

private struct SelectionMarquee: View {
    let frame: CGRect

    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.10))
            .overlay {
                Rectangle()
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }
}

private struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 24
        var x: CGFloat = 0
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }

        var y: CGFloat = 0
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }

        return path
    }
}
