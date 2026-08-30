import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 永続化フォーマット（[Domain/Coding](../qool/Domain/Coding/)）の検証。
struct CanvasCodingTests {
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func roundTrip<T: Codable>(_ value: T) throws -> T {
        let data = try encoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - 色

    @Test func プリセット色が往復する() throws {
        let presets: [CanvasColor] = [.paper, .mint, .coral, .sky, .ink, .clear]

        for preset in presets {
            #expect(try CanvasCodingTests.roundTrip(preset) == preset)
        }
    }

    @Test func カスタム色が往復する() throws {
        let color = CanvasColor.custom(RGBAComponents(red: 0.25, green: 0.5, blue: 0.75, opacity: 0.4))

        #expect(try CanvasCodingTests.roundTrip(color) == color)
    }

    @Test func プリセット色は名前で保存される() throws {
        let json = try String(data: CanvasCodingTests.encoder().encode(CanvasColor.mint), encoding: .utf8)

        // 成分ではなく名前で持つ。後からプリセットの色味を変えても既存メモに反映されます。
        #expect(json == #"{"preset":"mint"}"#)
    }

    // MARK: - RGBAComponents

    @Test func 復号時に範囲外の成分が丸められる() throws {
        let json = #"{"red":2.5,"green":-1,"blue":0.5,"opacity":9}"#
        let components = try JSONDecoder().decode(RGBAComponents.self, from: Data(json.utf8))

        #expect(components.red == 1)
        #expect(components.green == 0)
        #expect(components.blue == 0.5)
        #expect(components.opacity == 1)
    }

    @Test func 復号時に非有限値が0になる() throws {
        // JSON は NaN や Infinity を直接表現できないため、文字列として読む設定を使う。
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        let json = #"{"red":"NaN","green":"Infinity","blue":0.5,"opacity":"-Infinity"}"#

        let components = try decoder.decode(RGBAComponents.self, from: Data(json.utf8))

        #expect(components.red == 0)
        #expect(components.green == 0)
        #expect(components.blue == 0.5)
        #expect(components.opacity == 0)
        // NaN が素通りしていると自分自身と等しくなくなる（Equatable の反射律が壊れる）。
        #expect(components == components)
    }

    @Test func 非有限値を渡した初期化でも反射律が保たれる() {
        let components = RGBAComponents(
            red: .nan,
            green: .infinity,
            blue: -.infinity,
            opacity: .nan
        )

        #expect(components == components)
        #expect(components.red == 0)
        #expect(components.green == 0)
        #expect(components.blue == 0)
        #expect(components.opacity == 0)
    }

    @Test func opacityを省略すると1になる() throws {
        let json = #"{"red":0.5,"green":0.5,"blue":0.5}"#

        let components = try JSONDecoder().decode(RGBAComponents.self, from: Data(json.utf8))

        #expect(components.opacity == 1)
    }

    // MARK: - CanvasElement

    @Test func 要素が往復する() throws {
        let element = CanvasElement(
            kind: .path,
            frame: CGRect(x: 12.5, y: 24, width: 100, height: 80),
            fillColor: .custom(RGBAComponents(red: 0.1, green: 0.2, blue: 0.3, opacity: 0.9)),
            strokeColor: .ink,
            strokeWidth: 3,
            showsStroke: true,
            cornerRadius: 6,
            text: "テスト\n改行",
            rotationAngleDegrees: 45,
            pathPoints: [NormalizedPoint(x: 0, y: 0), NormalizedPoint(x: 1, y: 0.5)],
            pathContours: [CanvasPathContour(points: [NormalizedPoint(x: 0.2, y: 0.3)], isClosed: false)],
            isClosedPath: false
        )

        #expect(try CanvasCodingTests.roundTrip(element) == element)
    }

    @Test func フレームが読める形で保存される() throws {
        let element = CanvasElement(
            kind: .rectangle,
            frame: CGRect(x: 1, y: 2, width: 3, height: 4),
            fillColor: .paper
        )
        let json = try String(data: CanvasCodingTests.encoder().encode(element), encoding: .utf8) ?? ""

        // CGRect の合成実装は [[1,2],[3,4]] という入れ子配列になり、手で直せません。
        #expect(json.contains(#""x":1"#))
        #expect(json.contains(#""y":2"#))
        #expect(json.contains(#""width":3"#))
        #expect(json.contains(#""height":4"#))
    }

    @Test func 欠けたキーは既定値で読める() throws {
        // 必須なのは id / kind / 座標 / fillColor だけ。
        // 今後プロパティが増えても、既存ファイルが読めなくなりません。
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "kind": "rectangle",
          "x": 0, "y": 0, "width": 10, "height": 10,
          "fillColor": { "preset": "paper" }
        }
        """
        let element = try JSONDecoder().decode(CanvasElement.self, from: Data(json.utf8))

        #expect(element.id == id)
        #expect(element.strokeColor == .ink)
        #expect(element.strokeWidth == 2)
        #expect(element.showsStroke)
        #expect(element.cornerRadius == 0)
        #expect(element.text == "テキスト")
        #expect(element.isClosedPath)
        #expect(element.unionSourceElements.isEmpty)
    }

    @Test func 結合の構成元が往復する() throws {
        let source = CanvasElement(
            kind: .rectangle,
            frame: CGRect(x: 0, y: 0, width: 50, height: 50),
            fillColor: .mint,
            cornerRadius: 8
        )
        let union = CanvasElement(
            kind: .path,
            frame: CGRect(x: 0, y: 0, width: 120, height: 60),
            fillColor: .mint,
            pathContours: [CanvasPathContour(points: [NormalizedPoint(x: 0, y: 0)])],
            unionSourceElements: [CanvasElementSnapshot(element: source)]
        )

        let decoded = try CanvasCodingTests.roundTrip(union)

        #expect(decoded == union)
        #expect(decoded.unionSourceElements.first?.cornerRadius == 8)
    }

    // MARK: - 画像

    @Test func 画像の参照と調整値が往復する() throws {
        let assetID = UUID()
        let element = CanvasElement(
            kind: .imageCutout,
            frame: CGRect(x: 4, y: 8, width: 120, height: 90),
            fillColor: .coral,
            imageAssetID: assetID,
            imageAdjustment: ImageAdjustment(
                opacity: 0.6,
                brightness: 0.2,
                padding: 24,
                blur: 3,
                blurDirection: .both
            )
        )

        let decoded = try CanvasCodingTests.roundTrip(element)

        #expect(decoded == element)
        #expect(decoded.imageAssetID == assetID)
        #expect(decoded.imageAdjustment.blurDirection == .both)
    }

    /// 画像のキーがない既存のメモも読めます。プロパティの追加でファイルが壊れないことの確認。
    @Test func 画像のキーがなくても読める() throws {
        let json = #"""
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "kind": "rectangle",
          "x": 0, "y": 0, "width": 10, "height": 10,
          "fillColor": {"preset": "mint"}
        }
        """#

        let decoded = try JSONDecoder().decode(CanvasElement.self, from: Data(json.utf8))

        #expect(decoded.imageAssetID == nil)
        #expect(decoded.imageAdjustment == .default)
    }

    @Test func 調整値の範囲外は復号時に丸められる() throws {
        let json = #"{"opacity": 5, "brightness": -9, "padding": 999, "blur": -1}"#

        let decoded = try JSONDecoder().decode(ImageAdjustment.self, from: Data(json.utf8))

        #expect(decoded.opacity == ImageAdjustment.opacityRange.upperBound)
        #expect(decoded.brightness == ImageAdjustment.brightnessRange.lowerBound)
        #expect(decoded.padding == ImageAdjustment.paddingRange.upperBound)
        #expect(decoded.blur == ImageAdjustment.blurRange.lowerBound)
    }

    /// 非有限値を素通しさせると `.nan != .nan` で `Equatable` の反射律が壊れます。
    @Test func 調整値に非有限値を渡しても反射律が保たれる() throws {
        let adjustment = ImageAdjustment(opacity: .nan, brightness: .infinity, padding: -.infinity, blur: .nan)

        #expect(adjustment == adjustment)
    }

    /// 結合の構成元も画像を持てます。スナップショットが `CanvasElement` の表現を使い回すためです。
    @Test func 結合の構成元でも画像の参照が往復する() throws {
        let assetID = UUID()
        let source = CanvasElement(
            kind: .imageCutout,
            frame: CGRect(x: 0, y: 0, width: 50, height: 50),
            fillColor: .coral,
            imageAssetID: assetID
        )
        let snapshot = CanvasElementSnapshot(element: source)

        let decoded = try CanvasCodingTests.roundTrip(snapshot)

        #expect(decoded.imageAssetID == assetID)
        #expect(decoded.element == source)
    }
}
