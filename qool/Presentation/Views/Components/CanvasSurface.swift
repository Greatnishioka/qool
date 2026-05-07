import SwiftUI

struct CanvasSurface: View {
    let elements: [CanvasElement]
    let draftElement: CanvasElement?
    let selectedElementIDs: Set<CanvasElement.ID>
    let unionSourceElements: [CanvasElementSnapshot]
    let selectedUnionSourceID: CanvasElementSnapshot.ID?
    let selectedTool: CanvasTool
    let onClearSelection: () -> Void
    let onHitTestElement: (CGPoint) -> CanvasElement.ID?
    let onHitTestUnionSource: (CGPoint) -> CanvasElementSnapshot.ID?
    let onSelectElements: (CGRect) -> Void
    let onUpdateDraft: (CGPoint, CGPoint, CGSize) -> Void
    let onCommitDraft: (CGPoint, CGPoint, CGSize) -> Void
    let onPlacePathPoint: (CGPoint, CGSize) -> Void
    let onSelectElement: (CanvasElement.ID) -> Void
    let onMoveSelectedElement: (CGSize, CGSize) -> Void
    let onDoubleTap: (CGPoint) -> Void
    let onSelectUnionSource: (CanvasElementSnapshot.ID) -> Void
    let onMoveUnionSource: (CanvasElementSnapshot.ID, CGSize, CGSize) -> Void

    @State private var activeDragTranslation: CGSize = .zero
    @State private var activeDragElementIDs: Set<CanvasElement.ID> = []
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
                            .stroke(Color(.separator).opacity(0.28), lineWidth: 0.5)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if selectedTool == .select {
                                    // ドラッグ開始時に、ヒットテストを行い、要素がヒットした場合はその要素を選択状態にする。複数選択されている場合は、ヒットした要素が選択されているかどうかで、ドラッグの対象を切り替える。どの要素もヒットしなかった場合は、選択用のドラッグとして扱う。
                                    if activeDragElementIDs.isEmpty, activeUnionSourceID == nil, selectionDragStart == nil {
                                        if let hitUnionSourceID = onHitTestUnionSource(value.startLocation) {
                                            onSelectUnionSource(hitUnionSourceID)
                                            activeUnionSourceID = hitUnionSourceID
                                        } else if let hitElementID = onHitTestElement(value.startLocation) {
                                            if selectedElementIDs.contains(hitElementID) {
                                                activeDragElementIDs = selectedElementIDs
                                            } else {
                                                onSelectElement(hitElementID)
                                                activeDragElementIDs = [hitElementID]
                                            }
                                        } else {
                                            selectionDragStart = value.startLocation
                                            selectionDragCurrent = value.location
                                        }
                                    }

                                    if activeDragElementIDs.isEmpty {
                                        if activeUnionSourceID == nil {
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

                                onUpdateDraft(value.startLocation, value.location, proxy.size)
                            }
                            .onEnded { value in
                                if selectedTool == .select {
                                    defer {
                                        activeDragElementIDs.removeAll()
                                        activeDragTranslation = .zero
                                        activeUnionSourceID = nil
                                        activeUnionSourceTranslation = .zero
                                        selectionDragStart = nil
                                        selectionDragCurrent = nil
                                    }

                                    if let activeUnionSourceID {
                                        onSelectUnionSource(activeUnionSourceID)
                                        if abs(value.translation.width) > 0.5 || abs(value.translation.height) > 0.5 {
                                            onMoveUnionSource(activeUnionSourceID, value.translation, proxy.size)
                                        }
                                        return
                                    }

                                    if !activeDragElementIDs.isEmpty {
                                        if activeDragElementIDs.count == 1, let activeDragElementID = activeDragElementIDs.first {
                                            onSelectElement(activeDragElementID)
                                        }

                                        if abs(value.translation.width) > 0.5 || abs(value.translation.height) > 0.5 {
                                            onMoveSelectedElement(value.translation, proxy.size)
                                        } else {
                                            registerTap(at: value.startLocation)
                                        }
                                        return
                                    }

                                    guard let selectionDragStart else {
                                        onClearSelection()
                                        return
                                    }

                                    let selectionFrame = normalizedFrame(from: selectionDragStart, to: value.location)
                                    if selectionFrame.width >= 4 || selectionFrame.height >= 4 {
                                        onSelectElements(selectionFrame)
                                    } else {
                                        onClearSelection()
                                    }
                                    return
                                }

                                if selectedTool == .path {
                                    if abs(value.translation.width) <= 4, abs(value.translation.height) <= 4 {
                                        onPlacePathPoint(value.location, proxy.size)
                                    }
                                    return
                                }

                                onCommitDraft(value.startLocation, value.location, proxy.size)
                            }
                    )

                ForEach(elements) { element in
                    let isSelected = selectedElementIDs.contains(element.id)
                    CanvasElementView(
                        element: element,
                        isSelected: isSelected,
                        selectedTool: selectedTool
                    )
                    .offset(activeDragElementIDs.contains(element.id) ? activeDragTranslation : .zero)
                    .allowsHitTesting(false)
                }

                ForEach(unionSourceElements) { sourceElement in
                    CanvasElementView(
                        element: sourceElement.element,
                        isSelected: selectedUnionSourceID == sourceElement.id,
                        selectedTool: selectedTool
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
            onDoubleTap(location)
            self.lastTapLocation = nil
            self.lastTapDate = nil
        } else {
            self.lastTapLocation = location
            self.lastTapDate = now
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
            if !element.pathContours.isEmpty {
                MultiContourPathShape(contours: element.pathContours)
                    .fill(element.fillColor.swiftUIColor.opacity(0.75), style: FillStyle(eoFill: true))
                    .overlay(strokeOverlay(MultiContourPathShape(contours: element.pathContours)))
            } else if element.pathPoints.isEmpty {
                LegacyPathShape()
                    .fill(element.fillColor.swiftUIColor.opacity(0.75))
                    .overlay(strokeOverlay(LegacyPathShape()))
            } else {
                BezierPathShape(points: element.pathPoints, isClosed: element.isClosedPath)
                    .fill(element.fillColor.swiftUIColor.opacity(element.isClosedPath ? 0.75 : 0.18))
                    .overlay(strokeOverlay(BezierPathShape(points: element.pathPoints, isClosed: element.isClosedPath)))
                    .overlay {
                        if !element.isClosedPath {
                            PathPointMarkers(points: element.pathPoints)
                        }
                    }
            }
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

private struct LegacyPathShape: Shape {
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

private struct BezierPathShape: Shape {
    let points: [NormalizedPoint]
    let isClosed: Bool

    func path(in rect: CGRect) -> Path {
        let cgPoints = points.map { point in
            CGPoint(
                x: rect.minX + rect.width * CGFloat(point.x),
                y: rect.minY + rect.height * CGFloat(point.y)
            )
        }

        var path = Path()
        guard let firstPoint = cgPoints.first else {
            return path
        }

        if cgPoints.count == 1 {
            path.addEllipse(in: CGRect(x: firstPoint.x - 4, y: firstPoint.y - 4, width: 8, height: 8))
            return path
        }

        path.move(to: firstPoint)

        if cgPoints.count == 2 {
            path.addLine(to: cgPoints[1])
        } else {
            addSmoothedSegments(to: &path, points: cgPoints)
        }

        if isClosed {
            if cgPoints.count > 2 {
                addClosingCurve(to: &path, points: cgPoints)
            }
            path.closeSubpath()
        }

        return path
    }

    private func addSmoothedSegments(to path: inout Path, points: [CGPoint]) {
        for index in 1..<points.count {
            if index == points.count - 1 {
                path.addQuadCurve(to: points[index], control: points[index - 1])
            } else {
                let midpoint = CGPoint(
                    x: (points[index].x + points[index + 1].x) / 2,
                    y: (points[index].y + points[index + 1].y) / 2
                )
                path.addQuadCurve(to: midpoint, control: points[index])
            }
        }
    }

    private func addClosingCurve(to path: inout Path, points: [CGPoint]) {
        guard let firstPoint = points.first, let lastPoint = points.last else {
            return
        }

        let midpoint = CGPoint(
            x: (lastPoint.x + firstPoint.x) / 2,
            y: (lastPoint.y + firstPoint.y) / 2
        )
        path.addQuadCurve(to: midpoint, control: lastPoint)
        path.addQuadCurve(to: firstPoint, control: firstPoint)
    }
}

private struct MultiContourPathShape: Shape {
    let contours: [CanvasPathContour]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        for contour in contours where !contour.points.isEmpty {
            let cgPoints = contour.points.map { point in
                CGPoint(
                    x: rect.minX + rect.width * CGFloat(point.x),
                    y: rect.minY + rect.height * CGFloat(point.y)
                )
            }

            guard let firstPoint = cgPoints.first else {
                continue
            }

            path.move(to: firstPoint)
            for point in cgPoints.dropFirst() {
                path.addLine(to: point)
            }
            if contour.isClosed {
                path.closeSubpath()
            }
        }

        return path
    }
}

private struct PathPointMarkers: View {
    let points: [NormalizedPoint]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                Circle()
                    .fill(index == 0 ? Color.accentColor : Color.white)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                    .position(
                        x: proxy.size.width * CGFloat(point.x),
                        y: proxy.size.height * CGFloat(point.y)
                    )
            }
        }
        .allowsHitTesting(false)
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
