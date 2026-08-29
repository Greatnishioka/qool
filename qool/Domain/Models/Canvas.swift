import CoreGraphics
import Foundation

nonisolated struct Canvas: Equatable, Hashable, Codable {
    var elements: [CanvasElement]

    init(elements: [CanvasElement] = []) {
        self.elements = elements
    }
}

nonisolated struct CanvasElement: Identifiable, Equatable, Hashable, Codable {
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

    init(
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
            isClosedPath: isClosedPath
        )
    }
}

nonisolated struct CanvasPathContour: Equatable, Hashable, Codable {
    var points: [NormalizedPoint]
    var isClosed: Bool

    init(points: [NormalizedPoint], isClosed: Bool = true) {
        self.points = points
        self.isClosed = isClosed
    }
}

nonisolated enum CanvasElementKind: String, CaseIterable, Identifiable, Hashable, Codable {
    case rectangle
    case path
    case line
    case text
    case imageCutout

    var id: String { rawValue }
}

nonisolated enum CanvasTool: String, CaseIterable, Identifiable, Hashable {
    case select = "選択"
    case rectangle = "矩形"
    case path = "パス"
    case line = "直線"
    case text = "テキスト"
    case image = "画像"

    var id: String { rawValue }
}

nonisolated enum CanvasColor: Identifiable, Hashable, Codable {
    case paper
    case mint
    case coral
    case sky
    case ink
    case clear
    /// 任意の色。成分は `RGBAComponents` が `0...1` に保つため、
    /// **範囲外や NaN を持つ状態は表現できません。**
    /// 生の `Double` を持っていた頃は、保存時に丸められて往復で値が変わっていました。
    case custom(RGBAComponents)

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
        case let .custom(components):
            "custom-\(components.red)-\(components.green)-\(components.blue)-\(components.opacity)"
        }
    }

    /// 色の実体。UI フレームワークには依存しない。
    /// SwiftUI の `Color` への変換は Presentation 層の extension が行う。
    var components: RGBAComponents {
        switch self {
        case .paper:
            RGBAComponents(red: 0.98, green: 0.96, blue: 0.88)
        case .mint:
            RGBAComponents(red: 0.66, green: 0.86, blue: 0.74)
        case .coral:
            RGBAComponents(red: 0.94, green: 0.48, blue: 0.42)
        case .sky:
            RGBAComponents(red: 0.48, green: 0.68, blue: 0.90)
        case .ink:
            RGBAComponents(red: 0.12, green: 0.14, blue: 0.16)
        case .clear:
            RGBAComponents(red: 0, green: 0, blue: 0, opacity: 0)
        case let .custom(components):
            components
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
