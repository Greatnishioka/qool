import CoreGraphics
import Foundation

nonisolated struct CanvasElementSnapshot: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    var kind: CanvasElementKind
    var frame: CGRect
    var fillColor: CanvasColor
    var strokeColor: CanvasColor
    var strokeWidth: CGFloat
    var showsStroke: Bool
    var cornerRadius: CGFloat
    var text: String
    var rotationAngleDegrees: Double
    var pathPoints: [NormalizedPoint]
    var pathContours: [CanvasPathContour]
    var isClosedPath: Bool
    var imageAssetID: UUID?
    var imageAdjustment: ImageAdjustment

    init(element: CanvasElement) {
        self.id = element.id
        self.kind = element.kind
        self.frame = element.frame
        self.fillColor = element.fillColor
        self.strokeColor = element.strokeColor
        self.strokeWidth = element.strokeWidth
        self.showsStroke = element.showsStroke
        self.cornerRadius = element.cornerRadius
        self.text = element.text
        self.rotationAngleDegrees = element.rotationAngleDegrees
        self.pathPoints = element.pathPoints
        self.pathContours = element.pathContours
        self.isClosedPath = element.isClosedPath
        self.imageAssetID = element.imageAssetID
        self.imageAdjustment = element.imageAdjustment
    }

    var element: CanvasElement {
        CanvasElement(
            id: id,
            kind: kind,
            frame: frame,
            fillColor: fillColor,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            showsStroke: showsStroke,
            cornerRadius: cornerRadius,
            text: text,
            rotationAngleDegrees: rotationAngleDegrees,
            pathPoints: pathPoints,
            pathContours: pathContours,
            isClosedPath: isClosedPath,
            imageAssetID: imageAssetID,
            imageAdjustment: imageAdjustment
        )
    }
}
