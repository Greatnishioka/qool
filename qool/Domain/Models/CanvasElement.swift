import CoreGraphics
import Foundation

nonisolated struct CanvasElement: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    var kind: CanvasElementKind
    var frame: CGRect
    var fillColor: CanvasColor
    var strokeColor: CanvasColor
    var strokeWidth: CGFloat
    /// 枠線を形のどちら側へ広げるか。
    var strokeAlignment: CanvasStrokeAlignment
    var showsStroke: Bool
    var cornerRadius: CGFloat
    var text: String
    var rotationAngleDegrees: Double
    var pathPoints: [NormalizedPoint]
    var pathContours: [CanvasPathContour]
    var isClosedPath: Bool
    /// 切り抜きの元画像。実体ではなく ID を持ちます（`ImageAssetRepositoryProtocol` が解決する）。
    var imageAssetID: UUID?
    var imageAdjustment: ImageAdjustment
    /// 切り詰める前の元画像。切り抜きを解除したときに戻る先です。
    /// 切り詰めていなければ `nil`。
    var imageSource: CutoutImageSource?
    /// 切り抜きのマスク。**`pathContours` より優先します。**
    /// マスクを持たない古いメモは `pathContours` で描きます。
    var cutoutMask: CutoutMaskReference?
    var unionSourceElements: [CanvasElementSnapshot]

    init(
        id: UUID = UUID(),
        kind: CanvasElementKind,
        frame: CGRect,
        fillColor: CanvasColor,
        strokeColor: CanvasColor = .ink,
        strokeWidth: CGFloat = 2,
        strokeAlignment: CanvasStrokeAlignment = .center,
        showsStroke: Bool = true,
        cornerRadius: CGFloat = 0,
        text: String = "テキスト",
        rotationAngleDegrees: Double = 0,
        pathPoints: [NormalizedPoint] = [],
        pathContours: [CanvasPathContour] = [],
        isClosedPath: Bool = true,
        imageAssetID: UUID? = nil,
        imageAdjustment: ImageAdjustment = .default,
        imageSource: CutoutImageSource? = nil,
        cutoutMask: CutoutMaskReference? = nil,
        unionSourceElements: [CanvasElementSnapshot] = []
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.strokeAlignment = strokeAlignment
        self.showsStroke = showsStroke
        self.cornerRadius = cornerRadius
        self.text = text
        self.rotationAngleDegrees = rotationAngleDegrees
        self.pathPoints = pathPoints
        self.pathContours = pathContours
        self.isClosedPath = isClosedPath
        self.imageAssetID = imageAssetID
        self.imageAdjustment = imageAdjustment
        self.imageSource = imageSource
        self.cutoutMask = cutoutMask
        self.unionSourceElements = unionSourceElements
    }
}
