import AppKit
import SwiftUI

/// キャンバス上の要素 1 つ分の描画。
///
/// 入力（ジェスチャ）は [CanvasSurface](CanvasSurface.swift) が持ち、こちらは描画だけを担います。
struct CanvasElementView: View {
    let element: CanvasElement
    let isSelected: Bool
    /// 切り抜きの元画像。取り込み前や読み込み失敗では `nil` で、その場合は枠だけ描きます。
    let image: NSImage?
    /// 切り抜きのマスク。**あれば輪郭より優先します。**
    /// 縁に中間の被覆率を持てるので、輪郭で抜くよりなめらかになります。
    /// まだ切り抜いていない要素や、マスクを読めなかった要素では `nil` です。
    var drawingMask: CutoutDrawingMask?

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
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var elementBody: some View {
        switch element.kind {
        case .rectangle:
            RoundedRectangle(cornerRadius: element.cornerRadius)
                .fill(element.fillColor.swiftUIColor)
                .overlay(strokeOverlay(RoundedRectangle(cornerRadius: element.cornerRadius)))
        case .path:
            if !element.pathContours.isEmpty {
                MultiContourPathShape(contours: element.pathContours)
                    .fill(element.fillColor.swiftUIColor.opacity(0.75), style: FillStyle(eoFill: true))
                    .overlay(strokeOverlay(MultiContourPathShape(contours: element.pathContours)))
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
            if let image {
                // 輪郭がなければ矩形のまま。切り抜き前でも画像は見えます。
                let cutoutShape = element.pathContours.isEmpty
                    ? AnyShape(Rectangle())
                    : AnyShape(MultiContourPathShape(contours: element.pathContours))

                // **縦横比は保ちません。** 輪郭は枠へ線形に写すので、
                // 画像だけ比を保つと、枠を非等比に変えたときに切り抜きが被写体から外れます。
                Image(nsImage: image)
                    .resizable()
                    .brightness(element.imageAdjustment.brightness)
                    .opacity(element.imageAdjustment.opacity)
                    .mask {
                        if let drawingMask {
                            rasterMask(drawingMask)
                        } else {
                            cutoutMask(cutoutShape)
                        }
                    }
                    .overlay(strokeOverlay(cutoutShape))
            } else {
                CutoutShape()
                    .fill(element.fillColor.swiftUIColor.opacity(0.75))
                    .overlay(strokeOverlay(CutoutShape()))
            }
        }
    }

    /// マスクで抜く。**余白は既に膨らませた形で渡ってきます。**
    /// ここで膨らませると、`body` が走るたびに画素をなめることになります。
    private func rasterMask(_ mask: CutoutDrawingMask) -> some View {
        GeometryReader { proxy in
            Image(decorative: mask.image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: mask.extent.width * proxy.size.width,
                    height: mask.extent.height * proxy.size.height
                )
                .offset(
                    x: mask.extent.minX * proxy.size.width,
                    y: mask.extent.minY * proxy.size.height
                )
        }
        // **明るさを不透明度として読み替えます。** `.mask` は不透明度で抜くため、
        // 明るさで持った画像をそのまま渡すと全面が不透明とみなされて何も抜けません。
        .luminanceToAlpha()
        .blur(radius: element.imageAdjustment.blur)
    }

    /// 輪郭で抜く。**マスクを読めなかったときの受け皿**です。余白とぼかしをここで足します。
    ///
    /// **輪郭の点を計算し直さず、太い線で膨らませています。**
    /// `ContourPadding` で座標を作り直すと、`body` が走るたびに数百点の再計算が入り、
    /// ドラッグ中の描画が持ちません。線幅による膨張は GPU 側で済みます。
    private func cutoutMask<S: Shape>(_ shape: S) -> some View {
        let adjustment = element.imageAdjustment
        // 外側ぼかしは、ぼけた分だけ形を先に広げないと、元の輪郭より内側へ食い込みます。
        let outset = adjustment.padding + (adjustment.blurDirection == .inward ? 0 : adjustment.blur)

        return ZStack {
            shape.fill(Color.white)

            if outset > 0 {
                shape.stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: outset * 2, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .blur(radius: adjustment.blur)
    }

    /// 枠線。**内側 / 外側は、倍の太さで描いてから片側を捨てて作ります。**
    /// 形を内外へずらして作り直す方法もありますが、`Shape` は一般には
    /// オフセットできず、輪郭の点を毎回計算し直すと `body` のたびに重くなります。
    @ViewBuilder
    private func strokeOverlay<S: Shape>(_ shape: S) -> some View {
        if element.showsStroke, element.strokeWidth > 0 {
            let color = element.strokeColor.swiftUIColor

            switch element.strokeAlignment {
            case .center:
                shape.stroke(color, lineWidth: element.strokeWidth)
            case .inside:
                shape.stroke(color, lineWidth: element.strokeWidth * 2)
                    .clipShape(shape, style: FillStyle(eoFill: true))
            case .outside:
                shape.stroke(color, lineWidth: element.strokeWidth * 2)
                    .mask { outwardStrokeMask(shape) }
            }
        }
    }

    /// 形の外側だけを残すマスク。内側を打ち抜いた矩形です。
    ///
    /// **矩形は枠線のぶん外へ広げます。** 枠の外側は要素の枠からはみ出すので、
    /// 広げないとマスクの縁で切られます。`padding` を矩形にだけ掛けるのが要点で、
    /// 全体に掛けると打ち抜く形まで一緒に拡大されます。
    private func outwardStrokeMask<S: Shape>(_ shape: S) -> some View {
        Rectangle()
            .fill(Color.white)
            .padding(-element.strokeWidth)
            .overlay {
                shape
                    .fill(Color.black, style: FillStyle(eoFill: true))
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
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
