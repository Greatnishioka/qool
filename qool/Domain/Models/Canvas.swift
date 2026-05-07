import Foundation
import SwiftUI

struct Canvas: Equatable, Hashable {
    var elements: [CanvasElement]

    init(elements: [CanvasElement] = []) {
        self.elements = elements
    }
}

struct CanvasElement: Identifiable, Equatable, Hashable {
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
    var unionSourceElements: [CanvasElementSnapshot]

    nonisolated init(
        id: UUID = UUID(),
        kind: CanvasElementKind,
        frame: CGRect,
        fillColor: CanvasColor,
        strokeColor: CanvasColor = .ink,
        strokeWidth: CGFloat = 2,
        showsStroke: Bool = true,
        cornerRadius: CGFloat = 0,
        text: String = "テキスト",
        rotationAngleDegrees: Double = 0,
        pathPoints: [NormalizedPoint] = [],
        pathContours: [CanvasPathContour] = [],
        isClosedPath: Bool = true,
        unionSourceElements: [CanvasElementSnapshot] = []
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.showsStroke = showsStroke
        self.cornerRadius = cornerRadius
        self.text = text
        self.rotationAngleDegrees = rotationAngleDegrees
        self.pathPoints = pathPoints
        self.pathContours = pathContours
        self.isClosedPath = isClosedPath
        self.unionSourceElements = unionSourceElements
    }
}

struct CanvasElementSnapshot: Identifiable, Equatable, Hashable {
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

    nonisolated init(element: CanvasElement) {
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
    }

    nonisolated var element: CanvasElement {
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
            isClosedPath: isClosedPath
        )
    }
}

struct CanvasPathContour: Equatable, Hashable {
    var points: [NormalizedPoint]
    var isClosed: Bool

    init(points: [NormalizedPoint], isClosed: Bool = true) {
        self.points = points
        self.isClosed = isClosed
    }
}

enum CanvasElementKind: String, CaseIterable, Identifiable, Hashable {
    case rectangle
    case path
    case line
    case text
    case imageCutout

    var id: String { rawValue }
}

enum CanvasTool: String, CaseIterable, Identifiable, Hashable {
    case select = "選択"
    case rectangle = "矩形"
    case path = "パス"
    case line = "直線"
    case text = "テキスト"
    case image = "画像"

    var id: String { rawValue }
}

enum CanvasColor: Identifiable, Hashable {
    case paper
    case mint
    case coral
    case sky
    case ink
    case clear
    case custom(red: Double, green: Double, blue: Double, opacity: Double)

    var id: String {
        switch self {
        case .paper:
            "paper"
        case .mint:
            "mint"
        case .coral:
            "coral"
        case .sky:
            "sky"
        case .ink:
            "ink"
        case .clear:
            "clear"
        case let .custom(red, green, blue, opacity):
            "custom-\(red)-\(green)-\(blue)-\(opacity)"
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .paper:
            Color(red: 0.98, green: 0.96, blue: 0.88)
        case .mint:
            Color(red: 0.66, green: 0.86, blue: 0.74)
        case .coral:
            Color(red: 0.94, green: 0.48, blue: 0.42)
        case .sky:
            Color(red: 0.48, green: 0.68, blue: 0.90)
        case .ink:
            Color(red: 0.12, green: 0.14, blue: 0.16)
        case .clear:
            Color.clear
        case let .custom(red, green, blue, opacity):
            Color(red: red, green: green, blue: blue, opacity: opacity)
        }
    }

    var displayName: String {
        switch self {
        case .paper:
            "紙"
        case .mint:
            "ミント"
        case .coral:
            "コーラル"
        case .sky:
            "スカイ"
        case .ink:
            "インク"
        case .clear:
            "透明"
        case .custom:
            "カスタム"
        }
    }
}
