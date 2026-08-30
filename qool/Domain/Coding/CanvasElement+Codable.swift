import CoreGraphics
import Foundation

/// 合成 `Codable` を使わない理由: 人が読める JSON にする /
/// 欠けたキーを既定値で埋める / 復号時にも不変条件を通す。
nonisolated extension CanvasElement {
    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case x
        case y
        case width
        case height
        case fillColor
        case strokeColor
        case strokeWidth
        case showsStroke
        case cornerRadius
        case text
        case rotationAngleDegrees
        case pathPoints
        case pathContours
        case isClosedPath
        case imageAssetID
        case imageAdjustment
        case unionSourceElements
    }

    /// 既定値は `init` のデフォルト引数と揃えています。
    /// キーが欠けていても既定値で読めるため、プロパティの追加でファイルが壊れません。
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            kind: try container.decode(CanvasElementKind.self, forKey: .kind),
            frame: CGRect(
                x: try container.decode(CGFloat.self, forKey: .x),
                y: try container.decode(CGFloat.self, forKey: .y),
                width: try container.decode(CGFloat.self, forKey: .width),
                height: try container.decode(CGFloat.self, forKey: .height)
            ),
            fillColor: try container.decode(CanvasColor.self, forKey: .fillColor),
            strokeColor: try container.decodeIfPresent(CanvasColor.self, forKey: .strokeColor) ?? .ink,
            strokeWidth: try container.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? 2,
            showsStroke: try container.decodeIfPresent(Bool.self, forKey: .showsStroke) ?? true,
            cornerRadius: try container.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 0,
            text: try container.decodeIfPresent(String.self, forKey: .text) ?? "テキスト",
            rotationAngleDegrees: try container.decodeIfPresent(Double.self, forKey: .rotationAngleDegrees) ?? 0,
            pathPoints: try container.decodeIfPresent([NormalizedPoint].self, forKey: .pathPoints) ?? [],
            pathContours: try container.decodeIfPresent([CanvasPathContour].self, forKey: .pathContours) ?? [],
            isClosedPath: try container.decodeIfPresent(Bool.self, forKey: .isClosedPath) ?? true,
            imageAssetID: try container.decodeIfPresent(UUID.self, forKey: .imageAssetID),
            imageAdjustment: try container.decodeIfPresent(
                ImageAdjustment.self,
                forKey: .imageAdjustment
            ) ?? .default,
            unionSourceElements: try container.decodeIfPresent(
                [CanvasElementSnapshot].self,
                forKey: .unionSourceElements
            ) ?? []
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(frame.origin.x, forKey: .x)
        try container.encode(frame.origin.y, forKey: .y)
        try container.encode(frame.size.width, forKey: .width)
        try container.encode(frame.size.height, forKey: .height)
        try container.encode(fillColor, forKey: .fillColor)
        try container.encode(strokeColor, forKey: .strokeColor)
        try container.encode(strokeWidth, forKey: .strokeWidth)
        try container.encode(showsStroke, forKey: .showsStroke)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(text, forKey: .text)
        try container.encode(rotationAngleDegrees, forKey: .rotationAngleDegrees)
        try container.encode(pathPoints, forKey: .pathPoints)
        try container.encode(pathContours, forKey: .pathContours)
        try container.encode(isClosedPath, forKey: .isClosedPath)
        try container.encodeIfPresent(imageAssetID, forKey: .imageAssetID)
        try container.encode(imageAdjustment, forKey: .imageAdjustment)
        try container.encode(unionSourceElements, forKey: .unionSourceElements)
    }
}
