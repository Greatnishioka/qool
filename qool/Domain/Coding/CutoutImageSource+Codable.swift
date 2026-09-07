import CoreGraphics
import Foundation

/// 合成 `Codable` を使わない理由: `CGRect` の既定表現が人の読めない形になるため。
/// 他のモデルと同じく、座標を平たい 4 つのキーへ展開します。
nonisolated extension CutoutImageSource {
    private enum CodingKeys: String, CodingKey {
        case assetID
        case x
        case y
        case width
        case height
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            assetID: try container.decode(UUID.self, forKey: .assetID),
            cropRect: CGRect(
                x: try container.decode(CGFloat.self, forKey: .x),
                y: try container.decode(CGFloat.self, forKey: .y),
                width: try container.decode(CGFloat.self, forKey: .width),
                height: try container.decode(CGFloat.self, forKey: .height)
            )
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(assetID, forKey: .assetID)
        try container.encode(cropRect.origin.x, forKey: .x)
        try container.encode(cropRect.origin.y, forKey: .y)
        try container.encode(cropRect.size.width, forKey: .width)
        try container.encode(cropRect.size.height, forKey: .height)
    }
}
