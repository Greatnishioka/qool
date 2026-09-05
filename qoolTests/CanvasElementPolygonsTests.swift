import CoreGraphics
import Foundation
import Testing
@testable import qool

/// [CanvasElementPolygons](../qool/Domain/Services/CanvasElementPolygons.swift) の検証。
///
/// **合成（Union）とフローティングメモの形が同じ変換を使う**ため、ここが崩れると両方が壊れます。
struct CanvasElementPolygonsTests {
    private let polygons = CanvasElementPolygons()

    @Test func 角丸の矩形は折れ線で近似される() throws {
        let element = CanvasElement(
            kind: .rectangle,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            fillColor: .paper,
            cornerRadius: 20
        )
        let points = try #require(polygons.filled(for: element).first)

        #expect(points.count > 4)
        // 角が丸いので、四隅そのものは通りません。
        #expect(!points.contains { $0.x == 0 && $0.y == 0 })
        #expect(points.allSatisfy { (0...100).contains($0.x) && (0...100).contains($0.y) })
    }

    @Test func 角丸が0なら四隅だけになる() throws {
        let element = CanvasElement(
            kind: .rectangle,
            frame: CGRect(x: 10, y: 20, width: 30, height: 40),
            fillColor: .paper
        )

        #expect(try #require(polygons.filled(for: element).first).count == 4)
    }

    @Test func 手描きの閉じたパスは曲線を刻んだ多角形になる() throws {
        let element = CanvasElement(
            kind: .path,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            fillColor: .paper,
            pathPoints: [
                NormalizedPoint(x: 0, y: 0),
                NormalizedPoint(x: 1, y: 0),
                NormalizedPoint(x: 1, y: 1),
                NormalizedPoint(x: 0, y: 1)
            ],
            isClosedPath: true
        )
        let points = try #require(polygons.filled(for: element).first)

        #expect(points.count > 4)
    }

    /// 閉じていないパスは塗る面を持ちません。合成の対象からも外れます。
    @Test func 閉じていないパスは面にならない() {
        let element = CanvasElement(
            kind: .path,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            fillColor: .paper,
            pathPoints: [NormalizedPoint(x: 0, y: 0), NormalizedPoint(x: 1, y: 1)],
            isClosedPath: false
        )

        #expect(polygons.filled(for: element).isEmpty)
        // ウィンドウの形としては掴めないと困るので、frame で代用します。
        #expect(polygons.outline(for: element).first?.count == 4)
    }

    @Test func 切り抜き済みの画像は輪郭がそのまま面になる() throws {
        let element = CanvasElement(
            kind: .imageCutout,
            frame: CGRect(x: 50, y: 50, width: 100, height: 100),
            fillColor: .paper,
            pathContours: [CanvasPathContour(points: [
                NormalizedPoint(x: 0, y: 0),
                NormalizedPoint(x: 1, y: 0),
                NormalizedPoint(x: 0.5, y: 1)
            ])]
        )
        let points = try #require(polygons.filled(for: element).first)

        #expect(points == [CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 50), CGPoint(x: 100, y: 150)])
    }
}
