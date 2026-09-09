import CoreGraphics
import Foundation

/// 合成 `Codable` を使わない理由: `CGRect` の既定表現が人の読めない形になるため。
/// 他のモデルと同じく、座標を平たい 4 つのキーへ展開します。
nonisolated extension CutoutMaskReference {
    private enum CodingKeys: String, CodingKey {
        case assetID
        case x
        case y
        case width
        case height
    }

    /// **成立しない範囲は読み込みで弾きます。** 手で書き換えられた JSON から
    /// 負の幅や非有限値が入ると、描画の段で壊れた `CGRect` になります。
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let extent = CGRect(
            x: try container.decode(CGFloat.self, forKey: .x),
            y: try container.decode(CGFloat.self, forKey: .y),
            width: try container.decode(CGFloat.self, forKey: .width),
            height: try container.decode(CGFloat.self, forKey: .height)
        )

        guard let reference = CutoutMaskReference(
            assetID: try container.decode(UUID.self, forKey: .assetID),
            extent: extent
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .width,
                in: container,
                debugDescription: "マスクの覆う範囲が成立していません: \(extent)"
            )
        }

        self = reference
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(assetID, forKey: .assetID)
        try container.encode(extent.origin.x, forKey: .x)
        try container.encode(extent.origin.y, forKey: .y)
        try container.encode(extent.size.width, forKey: .width)
        try container.encode(extent.size.height, forKey: .height)
    }
}
