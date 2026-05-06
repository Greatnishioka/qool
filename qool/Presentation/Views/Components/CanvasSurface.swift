import SwiftUI

struct CanvasSurface: View {
    let elements: [CanvasElement]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white)
                    .overlay {
                        GridPattern()
                            .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
                    }

                ForEach(elements) { element in
                    CanvasElementView(element: element)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct CanvasElementView: View {
    let element: CanvasElement

    var body: some View {
        Group {
            switch element.kind {
            case .rectangle:
                Rectangle()
                    .fill(element.fillColor.swiftUIColor)
                    .overlay(Rectangle().stroke(element.strokeColor.swiftUIColor, lineWidth: element.strokeWidth))
            case .curve:
                CurveShape()
                    .stroke(element.fillColor.swiftUIColor, lineWidth: max(4, element.strokeWidth * 2))
            case .textPath:
                RoundedRectangle(cornerRadius: 6)
                    .fill(element.fillColor.swiftUIColor.opacity(0.35))
                    .overlay {
                        Text("入力欄")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(element.strokeColor.swiftUIColor, style: StrokeStyle(lineWidth: element.strokeWidth, dash: [6, 4])))
            case .imageCutout:
                CutoutShape()
                    .fill(element.fillColor.swiftUIColor.opacity(0.75))
                    .overlay(CutoutShape().stroke(element.strokeColor.swiftUIColor, lineWidth: element.strokeWidth))
            }
        }
        .frame(width: element.frame.width, height: element.frame.height)
        .position(x: element.frame.midX, y: element.frame.midY)
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

private struct CurveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY),
            control2: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.maxY)
        )
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
