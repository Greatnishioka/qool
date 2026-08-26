import CoreGraphics
import Foundation

/// 永続化フォーマットの定義。
///
/// 合成された `Codable` に任せず手で書いているのは、次の 3 つを守るためです。
///
/// 1. **人が読める JSON にする。** `CGRect` の合成実装は `[[x, y], [w, h]]` という
///    入れ子の配列になり、[永続化方針](../../../docs/architecture/persistence.md)が
///    利点として挙げている「壊れたときに手で直せる」が成り立たなくなります。
/// 2. **欠けたキーを既定値で埋める。** 今後 `CanvasElement` にプロパティが増えても、
///    既存のファイルが読めなくなりません。
/// 3. **復号時にも不変条件を通す。** `RGBAComponents` は範囲外や NaN を弾く必要があります。

// MARK: - RGBAComponents

extension RGBAComponents {
    private enum CodingKeys: String, CodingKey {
        case red
        case green
        case blue
        case opacity
    }

    /// 復号値を必ず正規化 `init` に通す。
    /// 合成実装だと格納プロパティへ直接代入されるため、
    /// 手で書き換えられた JSON の NaN や範囲外の値がそのまま入ってしまいます。
    nonisolated init(from decoder: any Decoder) throws {
        // containerはjsonなのか、plistなのか、yamlなのかを抽象化して読み書きするための機能。
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            red: try container.decode(Double.self, forKey: .red),
            green: try container.decode(Double.self, forKey: .green),
            blue: try container.decode(Double.self, forKey: .blue),
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        )
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
        try container.encode(opacity, forKey: .opacity)
    }
}

// MARK: - CanvasColor

extension CanvasColor {
    private enum CodingKeys: String, CodingKey {
        case preset
        case custom
    }

    /// プリセット名。`CanvasColor` の case 名と一致させています。
    private enum Preset: String, Codable {
        case paper
        case mint
        case coral
        case sky
        case ink
        case clear
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let preset = try container.decodeIfPresent(Preset.self, forKey: .preset) {
            switch preset {
            case .paper:
                self = .paper
            case .mint:
                self = .mint
            case .coral:
                self = .coral
            case .sky:
                self = .sky
            case .ink:
                self = .ink
            case .clear:
                self = .clear
            }

            return
        }

        let components = try container.decode(RGBAComponents.self, forKey: .custom)
        self = .custom(
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: components.opacity
        )
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .paper:
            try container.encode(Preset.paper, forKey: .preset)
        case .mint:
            try container.encode(Preset.mint, forKey: .preset)
        case .coral:
            try container.encode(Preset.coral, forKey: .preset)
        case .sky:
            try container.encode(Preset.sky, forKey: .preset)
        case .ink:
            try container.encode(Preset.ink, forKey: .preset)
        case .clear:
            try container.encode(Preset.clear, forKey: .preset)
        case let .custom(red, green, blue, opacity):
            try container.encode(
                RGBAComponents(red: red, green: green, blue: blue, opacity: opacity),
                forKey: .custom
            )
        }
    }
}

// MARK: - CanvasElement

extension CanvasElement {
    fileprivate enum CodingKeys: String, CodingKey {
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
        case unionSourceElements
    }

    /// 既定値は `init` のデフォルト引数と揃えています。
    /// キーが欠けていても既定値で読めるため、プロパティの追加でファイルが壊れません。
    nonisolated init(from decoder: any Decoder) throws {
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
            unionSourceElements: try container.decodeIfPresent(
                [CanvasElementSnapshot].self,
                forKey: .unionSourceElements
            ) ?? []
        )
    }

    nonisolated func encode(to encoder: any Encoder) throws {
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
        try container.encode(unionSourceElements, forKey: .unionSourceElements)
    }
}

// MARK: - CanvasElementSnapshot

extension CanvasElementSnapshot {
    /// スナップショットは `CanvasElement` から `unionSourceElements` を除いたものなので、
    /// 同じ表現を使い回します。定義を二重に持たないことが目的です。
    ///
    /// 結合はネストしません（結合結果をさらに結合しても構成元は 1 段のまま）。
    /// スナップショット自身が構成元を持つことはないため、この往復で情報は落ちません。
    nonisolated init(from decoder: any Decoder) throws {
        self.init(element: try CanvasElement(from: decoder))
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        try element.encode(to: encoder)
    }
}
