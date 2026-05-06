import SwiftUI

struct CanvasSurface: View {
    let elements: [CanvasElement]
    let draftElement: CanvasElement?
    let selectedElementID: CanvasElement.ID?
    let selectedTool: CanvasTool
    let onClearSelection: () -> Void
    let onHitTestElement: (CGPoint) -> CanvasElement.ID?
    let onUpdateDraft: (CGPoint, CGPoint, CGSize) -> Void
    let onCommitDraft: (CGPoint, CGPoint, CGSize) -> Void
    let onSelectElement: (CanvasElement.ID) -> Void
    let onMoveSelectedElement: (CGSize, CGSize) -> Void

    @State private var activeDragTranslation: CGSize = .zero
    @State private var activeDragElementID: CanvasElement.ID?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.white)
                    .overlay {
                        GridPattern()
                            .stroke(Color(.separator).opacity(0.28), lineWidth: 0.5)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedTool == .select {
                            onClearSelection()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if selectedTool == .select {
                                    if activeDragElementID == nil {
                                        activeDragElementID = onHitTestElement(value.startLocation)
                                        if let activeDragElementID {
                                            onSelectElement(activeDragElementID)
                                        }
                                    }

                                    activeDragTranslation = activeDragElementID == nil ? .zero : value.translation
                                    return
                                }

                                onUpdateDraft(value.startLocation, value.location, proxy.size)
                            }
                            .onEnded { value in
                                if selectedTool == .select {
                                    defer {
                                        activeDragElementID = nil
                                        activeDragTranslation = .zero
                                    }

                                    guard let activeDragElementID else {
                                        onClearSelection()
                                        return
                                    }

                                    onSelectElement(activeDragElementID)
                                    if abs(value.translation.width) > 0.5 || abs(value.translation.height) > 0.5 {
                                        onMoveSelectedElement(value.translation, proxy.size)
                                    }
                                    return
                                }

                                onCommitDraft(value.startLocation, value.location, proxy.size)
                            }
                    )

                ForEach(elements) { element in
                    let isSelected = selectedElementID == element.id
                    CanvasElementView(
                        element: element,
                        isSelected: isSelected,
                        selectedTool: selectedTool
                    )
                    .offset(activeDragElementID == element.id ? activeDragTranslation : .zero)
                    .allowsHitTesting(false)
                }

                if let draftElement {
                    CanvasElementView(
                        element: draftElement,
                        isSelected: true,
                        selectedTool: .select
                    )
                    .opacity(0.72)
                    .allowsHitTesting(false)
                }
            }
            .clipShape(Rectangle())
        }
    }
}

private struct CanvasElementView: View {
    let element: CanvasElement
    let isSelected: Bool
    let selectedTool: CanvasTool

    var body: some View {
        elementBody
            .frame(width: element.frame.width, height: max(2, element.frame.height))
            .overlay {
                if isSelected {
                    SelectionOutline()
                }
            }
            .rotationEffect(.degrees(element.rotationAngleDegrees))
            .position(x: element.frame.midX, y: element.frame.midY)
            .contentShape(Rectangle())
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var elementBody: some View {
        switch element.kind {
        case .rectangle:
            Rectangle()
                .fill(element.fillColor.swiftUIColor)
                .overlay(strokeOverlay(Rectangle()))
        case .path:
            PathShape()
                .fill(element.fillColor.swiftUIColor.opacity(0.75))
                .overlay(strokeOverlay(PathShape()))
        case .line:
            LineShape()
                .stroke(
                    element.strokeColor.swiftUIColor,
                    style: StrokeStyle(lineWidth: max(1, element.strokeWidth), lineCap: .round)
                )
        case .text:
            Text(element.text.isEmpty ? "テキスト" : element.text)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(element.strokeColor.swiftUIColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(element.fillColor.swiftUIColor)
                .overlay(strokeOverlay(Rectangle()))
        case .imageCutout:
            CutoutShape()
                .fill(element.fillColor.swiftUIColor.opacity(0.75))
                .overlay(strokeOverlay(CutoutShape()))
        }
    }

    @ViewBuilder
    private func strokeOverlay<S: Shape>(_ shape: S) -> some View {
        if element.showsStroke {
            shape.stroke(element.strokeColor.swiftUIColor, lineWidth: element.strokeWidth)
        }
    }
}

private struct SelectionOutline: View {
    var body: some View {
        Rectangle()
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .overlay(alignment: .topLeading) { handle }
            .overlay(alignment: .topTrailing) { handle }
            .overlay(alignment: .bottomLeading) { handle }
            .overlay(alignment: .bottomTrailing) { handle }
    }

    private var handle: some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 8, height: 8)
            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1.5))
            .offset(x: 0, y: 0)
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

private struct PathShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.06),
            control2: CGPoint(x: rect.minX + rect.width * 0.76, y: rect.maxY - rect.height * 0.04)
        )
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.24, y: rect.maxY - rect.height * 0.12))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY - rect.height * 0.22),
            control1: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.02),
            control2: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.maxY - rect.height * 0.58)
        )
        path.closeSubpath()
        return path
    }
}

private struct LineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct CutoutShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.78, y: rect.minY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.minY + rect.height * 0.72))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.88))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.52))
        path.closeSubpath()
        return path
    }
}
