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

    // MARK: - 余白とぼかし

    private func bounds(of points: [CGPoint]) -> CGRect {
        let first = CGRect(origin: points[0], size: .zero)

        return points.dropFirst().reduce(first) { partialResult, point in
            partialResult.union(CGRect(origin: point, size: .zero))
        }
    }

    /// 円に近い輪郭。矩形とみなされると `ContourPadding` が bounds を広げる経路へ入るため、
    /// 押し出しの向きを見たいここでは丸い形を使います。
    private func circleContour(radius: Double = 0.3, count: Int = 24) -> CanvasPathContour {
        CanvasPathContour(points: (0..<count).map { index in
            let angle = Double(index) / Double(count) * 2 * .pi

            return NormalizedPoint(x: 0.5 + cos(angle) * radius, y: 0.5 + sin(angle) * radius)
        })
    }

    private func imageElement(contours: [CanvasPathContour], adjustment: ImageAdjustment) -> CanvasElement {
        CanvasElement(
            kind: .imageCutout,
            frame: CGRect(x: 0, y: 0, width: 200, height: 200),
            fillColor: .clear,
            showsStroke: false,
            pathContours: contours,
            imageAssetID: UUID(),
            imageAdjustment: adjustment
        )
    }

    /// **描画は余白とぼかしのぶん外へ広がります。** 形が輪郭のままだと、
    /// フローティングメモのウィンドウがそこを切り落とします。
    @Test func 余白のぶん外形が広がる() throws {
        let contour = circleContour()
        let plain = imageElement(contours: [contour], adjustment: .default)
        let padded = imageElement(contours: [contour], adjustment: ImageAdjustment(padding: 12))

        let plainBounds = bounds(of: try #require(polygons.filled(for: plain).first))
        let paddedBounds = bounds(of: try #require(polygons.filled(for: padded).first))

        #expect(paddedBounds.width > plainBounds.width)
        #expect(paddedBounds.height > plainBounds.height)
    }

    @Test func 外向きのぼかしも外形に含まれる() throws {
        let contour = circleContour()
        let padded = imageElement(contours: [contour], adjustment: ImageAdjustment(padding: 12))
        let blurred = imageElement(
            contours: [contour],
            adjustment: ImageAdjustment(padding: 12, blur: 10, blurDirection: .outward)
        )

        let paddedBounds = bounds(of: try #require(polygons.filled(for: padded).first))
        let blurredBounds = bounds(of: try #require(polygons.filled(for: blurred).first))

        #expect(blurredBounds.width > paddedBounds.width)
    }

    /// 内側ぼかしは輪郭の内側で完結するので、外形は変わりません。
    @Test func 内向きのぼかしは外形を変えない() throws {
        let contour = circleContour()
        let padded = imageElement(contours: [contour], adjustment: ImageAdjustment(padding: 12))
        let blurred = imageElement(
            contours: [contour],
            adjustment: ImageAdjustment(padding: 12, blur: 10, blurDirection: .inward)
        )

        let paddedBounds = bounds(of: try #require(polygons.filled(for: padded).first))
        let blurredBounds = bounds(of: try #require(polygons.filled(for: blurred).first))

        #expect(abs(blurredBounds.width - paddedBounds.width) < 0.0001)
    }

    /// **穴は縮みます。** 外周と同じ向きへ押し出すと、余白を足したのに抜けが広がります。
    @Test func 余白を足すと穴は縮む() throws {
        let outer = circleContour(radius: 0.45)
        // 穴は外周と逆向きにします。iOverlay の出力もこの向きで返ります。
        let hole = CanvasPathContour(points: circleContour(radius: 0.15).points.reversed())
        let element = imageElement(
            contours: [outer, hole],
            adjustment: ImageAdjustment(padding: 12)
        )

        let plain = imageElement(contours: [outer, hole], adjustment: .default)
        let plainHole = bounds(of: try #require(polygons.filled(for: plain).last))
        let paddedHole = bounds(of: try #require(polygons.filled(for: element).last))

        #expect(paddedHole.width < plainHole.width)
    }

    // MARK: - 枠線の広がる向き

    private func strokedRectangle(_ alignment: CanvasStrokeAlignment) -> CanvasElement {
        CanvasElement(
            kind: .rectangle,
            frame: CGRect(x: 20, y: 20, width: 100, height: 60),
            fillColor: .paper,
            strokeWidth: 8,
            strokeAlignment: alignment
        )
    }

    /// **外側枠線はウィンドウの形に含めます。** 含めないと、
    /// デスクトップに貼ったときに枠線がウィンドウの縁で切られます。
    @Test func 外側枠線のぶん外形が広がる() throws {
        let centered = bounds(of: try #require(polygons.filled(for: strokedRectangle(.center)).first))
        let outside = bounds(of: try #require(polygons.filled(for: strokedRectangle(.outside)).first))

        #expect(abs(outside.width - (centered.width + 16)) < 0.0001)
        #expect(abs(outside.minX - (centered.minX - 8)) < 0.0001)
    }

    @Test func 内側枠線は外形を変えない() throws {
        let centered = bounds(of: try #require(polygons.filled(for: strokedRectangle(.center)).first))
        let inside = bounds(of: try #require(polygons.filled(for: strokedRectangle(.inside)).first))

        #expect(abs(inside.width - centered.width) < 0.0001)
    }

    /// 枠線がオフなら向きに関係なく広がりません。
    @Test func 枠線がオフなら外側でも広がらない() throws {
        var element = strokedRectangle(.outside)
        element.showsStroke = false

        let hidden = bounds(of: try #require(polygons.filled(for: element).first))
        let centered = bounds(of: try #require(polygons.filled(for: strokedRectangle(.center)).first))

        #expect(abs(hidden.width - centered.width) < 0.0001)
    }

    /// 紙を敷く形には含めません。枠線の外まで紙を敷くと縁が硬くなります。
    @Test func 紙の形には外側枠線を含めない() throws {
        let element = strokedRectangle(.outside)
        let withStroke = bounds(of: try #require(polygons.filled(for: element).first))
        let paper = bounds(of: try #require(polygons.filled(for: element, includingAdjustment: false).first))

        #expect(paper.width < withStroke.width)
    }
}
