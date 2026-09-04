import CoreGraphics
import Foundation
import Testing
@testable import qool

/// [RectangularGuideContour](../qool/Domain/Services/RectangularGuideContour.swift) の検証。
struct RectangularGuideContourTests {
    private let contour = RectangularGuideContour()

    private func circle(radius: CGFloat, count: Int = 40) -> [CGPoint] {
        (0..<count).map { index in
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
            return CGPoint(x: 0.5 + cos(angle) * radius, y: 0.5 + sin(angle) * radius)
        }
    }

    @Test func 矩形輪郭は1辺あたり決まった点数を持つ() {
        let points = contour.rectangularContour(for: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))

        #expect(points.count == RectangularGuideContour.pointsPerSide * 4)
    }

    @Test func 矩形輪郭は元の矩形に一致する() {
        let rect = CGRect(x: 0.2, y: 0.3, width: 0.5, height: 0.4)

        let points = contour.rectangularContour(for: rect)

        #expect(abs(points.map(\.x).min()! - rect.minX) < 1e-12)
        #expect(abs(points.map(\.x).max()! - rect.maxX) < 1e-12)
        #expect(abs(points.map(\.y).min()! - rect.minY) < 1e-12)
        #expect(abs(points.map(\.y).max()! - rect.maxY) < 1e-12)
    }

    /// 正規化座標なので、はみ出した矩形は切り詰められます。
    @Test func 単位範囲の外へはみ出した矩形は切り詰められる() {
        let points = contour.rectangularContour(for: CGRect(x: -0.5, y: -0.5, width: 2, height: 2))

        #expect(points.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 })
    }

    // MARK: - 判定

    @Test func 矩形のガイドは矩形とみなされる() {
        let rectangle = contour.rectangularContour(for: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))

        #expect(contour.isRectangleLikeGuide(rectangle))
    }

    @Test func 円のガイドは矩形とみなされない() {
        #expect(contour.isRectangleLikeGuide(circle(radius: 0.3)) == false)
    }

    /// 小さすぎるガイドは判定しません。指が滑っただけの入力を矩形に化けさせないためです。
    @Test func 極端に小さいガイドは矩形とみなされない() {
        let tiny = contour.rectangularContour(for: CGRect(x: 0.5, y: 0.5, width: 0.02, height: 0.02))

        #expect(contour.isRectangleLikeGuide(tiny) == false)
    }

    @Test func 矩形輪郭は矩形らしい輪郭と判定される() {
        let rectangle = contour.rectangularContour(for: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))

        #expect(contour.isRectangleLikeContour(rectangle))
    }

    @Test func 円の輪郭は矩形らしい輪郭と判定されない() {
        #expect(contour.isRectangleLikeContour(circle(radius: 0.3, count: 80)) == false)
    }

    // MARK: - 検出

    @Test func 矩形のガイドからは矩形の輪郭が得られる() throws {
        let guide = contour.rectangularContour(for: CGRect(x: 0.2, y: 0.25, width: 0.6, height: 0.5))

        let detected = try #require(contour.detectContour(from: guide))

        #expect(abs(detected.map(\.x).min()! - 0.2) < 1e-12)
        #expect(abs(detected.map(\.y).max()! - 0.75) < 1e-12)
    }

    @Test func 円のガイドからは検出されない() {
        #expect(contour.detectContour(from: circle(radius: 0.3)) == nil)
    }

    @Test func 点が少なすぎるガイドからは検出されない() {
        #expect(contour.detectContour(from: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9)]) == nil)
    }
}
