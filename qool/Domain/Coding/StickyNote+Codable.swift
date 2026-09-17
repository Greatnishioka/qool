import CoreGraphics
import Foundation

/// 合成 `Codable` を使わない理由: **`texts` の鍵が `UUID` だからです。**
///
/// `JSONEncoder` は `String` / `Int` 以外を鍵に持つ辞書を、
/// **鍵と値を交互に並べた配列**として書き出します。人が読めなくなり、
/// 手で直すこともできません。鍵は `uuidString` に直して素直な辞書にします。
///
/// 欠けたキーを既定値で埋める方針は [CanvasElement](CanvasElement+Codable.swift) と同じです。
nonisolated extension StickyNote: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case templateID
        case title
        case x
        case y
        case texts
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let texts = try container.decodeIfPresent([String: String].self, forKey: .texts) ?? [:]

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            templateID: try container.decode(UUID.self, forKey: .templateID),
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            origin: CGPoint(
                x: try container.decodeIfPresent(CGFloat.self, forKey: .x) ?? 0,
                y: try container.decodeIfPresent(CGFloat.self, forKey: .y) ?? 0
            ),
            // **読めない鍵は捨てます。** 直せない値を抱えたままにしても使い道がありません。
            //
            // **`uniqueKeysWithValues` は使えません。** `UUID(uuidString:)` は
            // 大文字と小文字のどちらも受けるので、同じ id が 2 通りの綴りで入っていると
            // **重複した鍵で落ちます**（投げないので、読み飛ばしでは救えません）。
            texts: texts.reduce(into: [:]) { result, pair in
                guard let id = UUID(uuidString: pair.key) else {
                    return
                }

                result[id] = pair.value
            },
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(templateID, forKey: .templateID)
        try container.encode(title, forKey: .title)
        try container.encode(origin.x, forKey: .x)
        try container.encode(origin.y, forKey: .y)
        try container.encode(
            Dictionary(uniqueKeysWithValues: texts.map { ($0.key.uuidString, $0.value) }),
            forKey: .texts
        )
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
