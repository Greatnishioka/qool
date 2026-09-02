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

    @State private var activeDragTranslation: CGSize = .zero
    @State private var activeDragElementIDs: Set<CanvasElement.ID> = []
    @State private var activeToggleElementID: CanvasElement.ID?
    @State private var activeUnionSourceID: CanvasElementSnapshot.ID?
    @State private var activeUnionSourceTranslation: CGSize = .zero
    @State private var selectionDragStart: CGPoint?
    @State private var selectionDragCurrent: CGPoint?
    @State private var lastTapLocation: CGPoint?
    @State private var lastTapDate: Date?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                canvasBackground
                    .gesture(canvasGesture(in: proxy.size))

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
            .offset(activeDragElementIDs.contains(element.id) ? activeDragTranslation : .zero)
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
            .offset(activeUnionSourceID == sourceElement.id ? activeUnionSourceTranslation : .zero)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var marqueeLayer: some View {
        if let selectionDragStart, let selectionDragCurrent {
            SelectionMarquee(frame: normalizedFrame(from: selectionDragStart, to: selectionDragCurrent))
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

    private func canvasGesture(in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { handleDragChanged($0, in: canvasSize) }
            .onEnded { handleDragEnded($0, in: canvasSize) }
    }

    private func handleDragChanged(_ value: DragGesture.Value, in canvasSize: CGSize) {

        if selectedTool == .select {
            // 対象はドラッグ開始時に一度だけ決め、以降は変えません。
            // 途中で決め直すと、指を動かしている最中に掴む要素が入れ替わります。
            if activeDragElementIDs.isEmpty, activeToggleElementID == nil, activeUnionSourceID == nil, selectionDragStart == nil {
                if let hitUnionSourceID = viewModel.unionSourceID(at: value.startLocation) {
                    viewModel.selectUnionSource(id: hitUnionSourceID)
                    activeUnionSourceID = hitUnionSourceID
                } else if let hitElementID = viewModel.elementID(at: value.startLocation) {
                    if isShiftSelectionActive {
                        activeToggleElementID = hitElementID
                    } else if selectedElementIDs.contains(hitElementID) {
                        activeDragElementIDs = selectedElementIDs
                    } else {
                        viewModel.selectElement(id: hitElementID)
                        activeDragElementIDs = [hitElementID]
                    }
                } else {
                    selectionDragStart = value.startLocation
                    selectionDragCurrent = value.location
                }
            }

            if activeDragElementIDs.isEmpty {
                if activeToggleElementID != nil {
                    return
                } else if activeUnionSourceID == nil {
                    selectionDragCurrent = value.location
                } else {
                    activeUnionSourceTranslation = value.translation
                }
            } else {
                activeDragTranslation = value.translation
            }
            return
        }

        if selectedTool == .path {
            return
        }

        viewModel.updateDraft(from: value.startLocation, to: value.location, canvasSize: canvasSize)

    }

    private func handleDragEnded(_ value: DragGesture.Value, in canvasSize: CGSize) {

        if selectedTool == .select {
            defer {
                activeDragElementIDs.removeAll()
                activeDragTranslation = .zero
                activeToggleElementID = nil
                activeUnionSourceID = nil
                activeUnionSourceTranslation = .zero
                selectionDragStart = nil
                selectionDragCurrent = nil
            }

            if let activeToggleElementID {
                if abs(value.translation.width) <= Threshold.tapSlop, abs(value.translation.height) <= Threshold.tapSlop {
                    viewModel.toggleElementSelection(id: activeToggleElementID)
                }
                return
            }

            if let activeUnionSourceID {
                viewModel.selectUnionSource(id: activeUnionSourceID)
                if abs(value.translation.width) > Threshold.moveEpsilon || abs(value.translation.height) > Threshold.moveEpsilon {
                    viewModel.moveUnionSource(id: activeUnionSourceID, by: value.translation, canvasSize: canvasSize)
                }
                return
            }

            if !activeDragElementIDs.isEmpty {
                if abs(value.translation.width) > Threshold.moveEpsilon || abs(value.translation.height) > Threshold.moveEpsilon {
                    viewModel.moveSelectedElement(by: value.translation, canvasSize: canvasSize)
                } else {
                    if activeDragElementIDs.count == 1, let activeDragElementID = activeDragElementIDs.first {
                        viewModel.selectElement(id: activeDragElementID)
                    }
                    registerTap(at: value.startLocation)
                }
                return
            }

            guard let selectionDragStart else {
                viewModel.clearSelection()
                return
            }

            let selectionFrame = normalizedFrame(from: selectionDragStart, to: value.location)
            if selectionFrame.width >= Threshold.marqueeMinimum || selectionFrame.height >= Threshold.marqueeMinimum {
                viewModel.selectElements(in: selectionFrame)
            } else {
                viewModel.clearSelection()
            }
            return
        }

        if selectedTool == .path {
            if abs(value.translation.width) <= Threshold.tapSlop, abs(value.translation.height) <= Threshold.tapSlop {
                viewModel.placePathPoint(at: value.location, canvasSize: canvasSize)
            }
            return
        }

        viewModel.commitDraft(from: value.startLocation, to: value.location, canvasSize: canvasSize)

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

    private func registerTap(at location: CGPoint) {
        let now = Date()
        guard let lastTapLocation, let lastTapDate else {
            self.lastTapLocation = location
            self.lastTapDate = now
            return
        }

        let elapsedTime = now.timeIntervalSince(lastTapDate)
        let distance = hypot(location.x - lastTapLocation.x, location.y - lastTapLocation.y)
        if elapsedTime <= 0.35, distance <= 24 {
            viewModel.beginEditingUnionElement(at: location)
            self.lastTapLocation = nil
            self.lastTapDate = nil
        } else {
            self.lastTapLocation = location
            self.lastTapDate = now
        }
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
