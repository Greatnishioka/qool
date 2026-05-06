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
    var text: String
    var rotationAngleDegrees: Double

    init(
        id: UUID = UUID(),
        kind: CanvasElementKind,
        frame: CGRect,
        fillColor: CanvasColor,
        strokeColor: CanvasColor = .ink,
        strokeWidth: CGFloat = 2,
        showsStroke: Bool = true,
        text: String = "テキスト",
        rotationAngleDegrees: Double = 0
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.showsStroke = showsStroke
        self.text = text
        self.rotationAngleDegrees = rotationAngleDegrees
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

enum CanvasColor: String, CaseIterable, Identifiable, Hashable {
    case paper
    case mint
    case coral
    case sky
    case ink
    case clear

    var id: String { rawValue }

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
        }
    }
}
