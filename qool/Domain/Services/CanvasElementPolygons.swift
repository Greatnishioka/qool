import CoreGraphics
import Foundation

/// キャンバス要素を多角形へ変換する。座標はキャンバス上の絶対値です。
///
/// **合成（`UnionCanvasElementsUseCase`）とウィンドウの形（`BuildFloatingMemoOutlineUseCase`）で
/// 同じ変換が要るため、ここに集めています。**
nonisolated struct CanvasElementPolygons {
    /// 角丸を折れ線で近似する分割数の下限と上限。
    private static let minimumCornerSegments = 6
    private static let maximumCornerSegments = 16
    /// 曲線を折れ線で近似する分割数の下限と上限。
    private static let minimumCurveSamples = 10
    private static let maximumCurveSamples = 32

    private let contourPadding = ContourPadding()
    private let geometry = ContourGeometry()

    init() {}

    /// 塗られている部分の輪郭。線・テキスト・輪郭のない画像は空になります。
    ///
    /// - Parameter includingAdjustment: 画像の余白とぼかしで広がった分を含めるか。
    ///   **ウィンドウの形には含め、紙の色を敷く形には含めません。**
    ///   含めた形に紙を敷くと、ぼかした縁まで塗り潰されて硬い縁になります。
    func filled(for element: CanvasElement, includingAdjustment: Bool = true) -> [[CGPoint]] {
        rotated(unrotatedFilled(for: element, includingAdjustment: includingAdjustment), by: element)
    }

    private func unrotatedFilled(for element: CanvasElement, includingAdjustment: Bool) -> [[CGPoint]] {
        switch element.kind {
        case .rectangle:
            return [roundedRectanglePoints(for: element, outset: includingAdjustment ? outwardStrokeWidth(of: element) : 0)]
        case .path:
            return pathPolygons(for: element, includingAdjustment: includingAdjustment)
        case .imageCutout:
            let contours = includingAdjustment ? paddedContours(of: element) : element.pathContours
            return contourPolygons(of: contours, in: element.frame)
        case .line, .text:
            return []
        }
    }

    /// 画面上で要素が占める範囲の輪郭。`filled` が空なら `frame` の矩形で代用します。
    ///
    /// **線やテキストも掴めないと困る**ため、フローティングウィンドウの形にはこちらを使います。
    func outline(for element: CanvasElement, includingAdjustment: Bool = true) -> [[CGPoint]] {
        let polygons = filled(for: element, includingAdjustment: includingAdjustment)
        guard polygons.isEmpty else {
            return polygons
        }

        return rotated([rectanglePoints(of: element.frame)], by: element)
    }

    /// 描画は `rotationEffect` で枠の中心を軸に回します。**外形も同じだけ回さないと、
    /// 斜めの線がウィンドウのマスクから外れて切れます。**
    private func rotated(_ polygons: [[CGPoint]], by element: CanvasElement) -> [[CGPoint]] {
        guard element.rotationAngleDegrees != 0 else {
            return polygons
        }

        let radians = element.rotationAngleDegrees * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        let center = CGPoint(x: element.frame.midX, y: element.frame.midY)

        return polygons.map { polygon in
            polygon.map { point in
                let dx = point.x - center.x
                let dy = point.y - center.y

                return CGPoint(
                    x: center.x + dx * cosine - dy * sine,
                    y: center.y + dx * sine + dy * cosine
                )
            }
        }
    }

    // MARK: - 種類ごとの変換

    private func pathPolygons(for element: CanvasElement, includingAdjustment: Bool) -> [[CGPoint]] {
        guard element.isClosedPath else {
            return []
        }

        if !element.pathContours.isEmpty {
            let contours = includingAdjustment ? paddedContours(of: element) : element.pathContours
            return contourPolygons(of: contours, in: element.frame)
        }

        // **曲線のパスは広げません。** 点列から毎回曲線を引き直すため、
        // 外側枠線のぶんを足すには曲線を作り直す必要があります。
        return [sampledPathPoints(for: element)].filter { $0.count >= 3 }
    }

    /// 余白とぼかしで広がった分まで含めた輪郭。
    ///
    /// **描画と同じだけ膨らませないと、ウィンドウの形が絵より小さくなります。**
    /// 描画側は輪郭を太い線でなぞって膨らませており
    /// （[CanvasElementView](../../Presentation/Views/Components/CanvasElementView.swift) の `cutoutMask`）、
    /// こちらが輪郭のままだと、はみ出した余白とぼかしが切り落とされます。
    ///
    /// **穴は逆向きに縮めます。** 外周と同じ向きへ押し出すと穴まで広がり、
    /// 余白を足したのに抜けが大きくなります。
    private func paddedContours(of element: CanvasElement) -> [CanvasPathContour] {
        let outset = outwardExtent(of: element)

        guard outset > 0, element.frame.width > 0, element.frame.height > 0 else {
            return element.pathContours
        }

        let areas = element.pathContours.map { contour in
            geometry.signedArea(contour.points.map { CGPoint(x: $0.x, y: $0.y) })
        }

        guard let outerArea = areas.max(by: { abs($0) < abs($1) }), outerArea != 0 else {
            return element.pathContours
        }

        return zip(element.pathContours, areas).map { contour, area in
            let amount = (area > 0) == (outerArea > 0) ? outset : -outset
            let expanded = contourPadding.expanded(
                contour.points.map { CGPoint(x: $0.x, y: $0.y) },
                imageSize: element.frame.size,
                paddingPixels: amount
            )

            return CanvasPathContour(
                points: expanded.map { NormalizedPoint(x: Double($0.x), y: Double($0.y)) },
                isClosed: contour.isClosed
            )
        }
    }

    /// 描画が形の外へ広がる量。余白・外側ぼかし・外側枠線の合計です。
    private func outwardExtent(of element: CanvasElement) -> CGFloat {
        let adjustment = element.imageAdjustment
        // 外側ぼかしは、ぼけた分だけ形が外へ出ます。内側ぼかしは輪郭の内側で完結します。
        let blur = adjustment.blurDirection == .inward ? 0 : adjustment.blur
        // 画像以外は余白とぼかしを持たないので、枠線だけが効きます。
        let adjustmentOutset = element.kind == .imageCutout ? CGFloat(adjustment.padding + blur) : 0

        return adjustmentOutset + outwardStrokeWidth(of: element)
    }

    /// 外側へ描かれる枠線の太さ。内側・中央では 0 です。
    private func outwardStrokeWidth(of element: CanvasElement) -> CGFloat {
        guard element.showsStroke, element.strokeAlignment == .outside else {
            return 0
        }

        return max(0, element.strokeWidth)
    }

    private func contourPolygons(of contours: [CanvasPathContour], in frame: CGRect) -> [[CGPoint]] {
        contours
            .filter(\.isClosed)
            .map { contour in
                contour.points.map { absolutePoint($0, in: frame) }
            }
            .filter { $0.count >= 3 }
    }

    private func rectanglePoints(of frame: CGRect) -> [CGPoint] {
        [
            CGPoint(x: frame.minX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.maxY),
            CGPoint(x: frame.minX, y: frame.maxY)
        ]
    }

    private func roundedRectanglePoints(for element: CanvasElement, outset: CGFloat = 0) -> [CGPoint] {
        let frame = element.frame.insetBy(dx: -outset, dy: -outset)
        // 角丸も一緒に広げないと、外側枠線の角だけ形からはみ出します。
        let radius = min(max(element.cornerRadius + outset, 0), min(frame.width, frame.height) / 2)
        guard radius > 0 else {
            return rectanglePoints(of: frame)
        }

        let segmentCount = max(
            Self.minimumCornerSegments,
            min(Self.maximumCornerSegments, Int(radius / 3))
        )
        var points: [CGPoint] = []
        points.reserveCapacity(segmentCount * 4)

        let corners: [(center: CGPoint, start: CGFloat, end: CGFloat)] = [
            (CGPoint(x: frame.maxX - radius, y: frame.minY + radius), -.pi / 2, 0),
            (CGPoint(x: frame.maxX - radius, y: frame.maxY - radius), 0, .pi / 2),
            (CGPoint(x: frame.minX + radius, y: frame.maxY - radius), .pi / 2, .pi),
            (CGPoint(x: frame.minX + radius, y: frame.minY + radius), .pi, .pi * 1.5)
        ]

        for corner in corners {
            appendArcPoints(
                to: &points,
                center: corner.center,
                radius: radius,
                startAngle: corner.start,
                endAngle: corner.end,
                segmentCount: segmentCount
            )
        }

        return points
    }

    private func appendArcPoints(
        to points: inout [CGPoint],
        center: CGPoint,
        radius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat,
        segmentCount: Int
    ) {
        for step in 0...segmentCount {
            // 角の継ぎ目で同じ点を二度置かないようにします。
            if !points.isEmpty, step == 0 {
                continue
            }

            let progress = CGFloat(step) / CGFloat(segmentCount)
            let angle = startAngle + (endAngle - startAngle) * progress
            points.append(CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            ))
        }
    }

    /// 手書きパスの制御点を、描画と同じ二次ベジェで折れ線へ落とす。
    private func sampledPathPoints(for element: CanvasElement) -> [CGPoint] {
        let points = element.pathPoints.map { absolutePoint($0, in: element.frame) }
        guard let firstPoint = points.first else {
            return []
        }

        guard points.count > 2 else {
            return points
        }

        var sampledPoints: [CGPoint] = [firstPoint]
        var currentPoint = firstPoint

        for index in 1..<points.count {
            let endPoint: CGPoint
            let controlPoint: CGPoint

            if index == points.count - 1 {
                endPoint = points[index]
                controlPoint = points[index - 1]
            } else {
                endPoint = CGPoint(
                    x: (points[index].x + points[index + 1].x) / 2,
                    y: (points[index].y + points[index + 1].y) / 2
                )
                controlPoint = points[index]
            }

            sampledPoints.append(contentsOf: sampleQuadCurve(
                from: currentPoint,
                control: controlPoint,
                to: endPoint
            ))
            currentPoint = endPoint
        }

        let lastPoint = points[points.count - 1]
        let closingMidpoint = CGPoint(
            x: (lastPoint.x + firstPoint.x) / 2,
            y: (lastPoint.y + firstPoint.y) / 2
        )

        sampledPoints.append(contentsOf: sampleQuadCurve(
            from: currentPoint,
            control: lastPoint,
            to: closingMidpoint
        ))
        sampledPoints.append(contentsOf: sampleQuadCurve(
            from: closingMidpoint,
            control: firstPoint,
            to: firstPoint
        ))

        if let lastSample = sampledPoints.last, distance(from: lastSample, to: firstPoint) < 0.5 {
            sampledPoints.removeLast()
        }

        return sampledPoints
    }

    private func sampleQuadCurve(from startPoint: CGPoint, control: CGPoint, to endPoint: CGPoint) -> [CGPoint] {
        let sampleCount = max(
            Self.minimumCurveSamples,
            min(Self.maximumCurveSamples, Int(distance(from: startPoint, to: endPoint) / 8))
        )
        var points: [CGPoint] = []
        points.reserveCapacity(sampleCount)

        for step in 1...sampleCount {
            let t = CGFloat(step) / CGFloat(sampleCount)
            let inverseT = 1 - t

            let startWeight = inverseT * inverseT
            let controlWeight = 2 * inverseT * t
            let endWeight = t * t

            points.append(CGPoint(
                x: startWeight * startPoint.x + controlWeight * control.x + endWeight * endPoint.x,
                y: startWeight * startPoint.y + controlWeight * control.y + endWeight * endPoint.y
            ))
        }

        return points
    }

    private func distance(from startPoint: CGPoint, to endPoint: CGPoint) -> CGFloat {
        hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
    }

    private func absolutePoint(_ point: NormalizedPoint, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.minX + frame.width * CGFloat(point.x),
            y: frame.minY + frame.height * CGFloat(point.y)
        )
    }
}
