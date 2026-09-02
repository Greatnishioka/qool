import AppKit
import SwiftUI

struct CanvasSurface: View {
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
                Rectangle()
                    .fill(Color.white)
                    .overlay {
                        GridPattern()
                            .stroke(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 0.5)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if selectedTool == .select {
                                    // ドラッグ開始時に、ヒットテストを行い、要素がヒットした場合はその要素を選択状態にする。複数選択されている場合は、ヒットした要素が選択されているかどうかで、ドラッグの対象を切り替える。どの要素もヒットしなかった場合は、選択用のドラッグとして扱う。
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

                                viewModel.updateDraft(from: value.startLocation, to: value.location, canvasSize: proxy.size)
                            }
                            .onEnded { value in
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
                                        if abs(value.translation.width) <= 4, abs(value.translation.height) <= 4 {
                                            viewModel.toggleElementSelection(id: activeToggleElementID)
                                        }
                                        return
                                    }

                                    if let activeUnionSourceID {
                                        viewModel.selectUnionSource(id: activeUnionSourceID)
                                        if abs(value.translation.width) > 0.5 || abs(value.translation.height) > 0.5 {
                                            viewModel.moveUnionSource(id: activeUnionSourceID, by: value.translation, canvasSize: proxy.size)
                                        }
                                        return
                                    }

                                    if !activeDragElementIDs.isEmpty {
                                        if abs(value.translation.width) > 0.5 || abs(value.translation.height) > 0.5 {
                                            viewModel.moveSelectedElement(by: value.translation, canvasSize: proxy.size)
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
                                    if selectionFrame.width >= 4 || selectionFrame.height >= 4 {
                                        viewModel.selectElements(in: selectionFrame)
                                    } else {
                                        viewModel.clearSelection()
                                    }
                                    return
                                }

                                if selectedTool == .path {
                                    if abs(value.translation.width) <= 4, abs(value.translation.height) <= 4 {
                                        viewModel.placePathPoint(at: value.location, canvasSize: proxy.size)
                                    }
                                    return
                                }

                                viewModel.commitDraft(from: value.startLocation, to: value.location, canvasSize: proxy.size)
                            }
                    )

                ForEach(elements) { element in
                    let isSelected = selectedElementIDs.contains(element.id)
                    CanvasElementView(
                        element: element,
                        isSelected: isSelected
                    )
                    .offset(activeDragElementIDs.contains(element.id) ? activeDragTranslation : .zero)
                    .allowsHitTesting(false)
                }

                ForEach(unionSourceElements) { sourceElement in
                    CanvasElementView(
                        element: sourceElement.element,
                        isSelected: selectedUnionSourceID == sourceElement.id
                    )
                    .opacity(selectedUnionSourceID == sourceElement.id ? 0.62 : 0.34)
                    .offset(activeUnionSourceID == sourceElement.id ? activeUnionSourceTranslation : .zero)
                    .allowsHitTesting(false)
                }

                if let selectionDragStart, let selectionDragCurrent {
                    SelectionMarquee(frame: normalizedFrame(from: selectionDragStart, to: selectionDragCurrent))
                        .allowsHitTesting(false)
                }

                if let draftElement {
                    CanvasElementView(
                        element: draftElement,
                        isSelected: true
                    )
                    .opacity(0.72)
                    .allowsHitTesting(false)
                }

            }
            .clipShape(Rectangle())
        }
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
