import CoreGraphics
import Foundation
import Testing
@testable import qool

/// [ContourPadding](../qool/Domain/Services/ContourPadding.swift) の検証。
struct ContourPaddingTests {
    private let padding = ContourPadding()
    private let imageSize = CGSize(width: 800, height: 600)

    private func circle(radius: CGFloat, count: Int = 40) -> [CGPoint] {
        (0..<count).map { index in
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
            return CGPoint(x: 0.5 + cos(angle) * radius, y: 0.5 + sin(angle) * radius)
        }
    }

    private func pixelDistancesFromCenter(_ points: [CGPoint]) -> [CGFloat] {
        let pixels = points.map { CGPoint(x: $0.x * imageSize.width, y: $0.y * imageSize.height) }
        let center = CGPoint(
            x: pixels.map(\.x).reduce(0, +) / CGFloat(pixels.count),
            y: pixels.map(\.y).reduce(0, +) / CGFloat(pixels.count)
        )

        return pixels.map { hypot($0.x - center.x, $0.y - center.y) }
    }

    @Test func 余白が0なら何も変えない() {
        let points = circle(radius: 0.2)

        #expect(padding.expanded(points, imageSize: imageSize, paddingPixels: 0) == points)
    }

    @Test func 点が少なすぎる場合は何も変えない() {
        let points = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9)]

        #expect(padding.expanded(points, imageSize: imageSize, paddingPixels: 20) == points)
    }

    @Test func 画像サイズが0なら何も変えない() {
        let points = circle(radius: 0.2)

        #expect(padding.expanded(points, imageSize: .zero, paddingPixels: 20) == points)
    }

    /// 重心から各点への方向へ、指定したピクセル数だけ押し出します。
    @Test func 各点が重心から指定ピクセルだけ離れる() {
        let points = circle(radius: 0.2)
        let before = pixelDistancesFromCenter(points)

        let expandedPoints = padding.expanded(points, imageSize: imageSize, paddingPixels: 30)

        let after = pixelDistancesFromCenter(expandedPoints)
        for index in before.indices {
            #expect(abs(after[index] - (before[index] + 30)) < 0.001)
        }
    }

    @Test func 負の値を渡すと収縮する() {
        let points = circle(radius: 0.2)
        let before = pixelDistancesFromCenter(points)

        let shrunk = padding.expanded(points, imageSize: imageSize, paddingPixels: -25)

        let after = pixelDistancesFromCenter(shrunk)
        for index in before.indices {
            #expect(abs(after[index] - (before[index] - 25)) < 0.001)
        }
    }

    /// 矩形は重心から押し出さず、bounds を広げて作り直します。
    /// 放射状に押し出すと角だけが外へ飛び出して形が崩れるためです。
    @Test func 矩形は矩形のまま広がる() {
        let rectangle = RectangularGuideContour().rectangularContour(
            for: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        )

        let expandedPoints = padding.expanded(rectangle, imageSize: imageSize, paddingPixels: 40)

        // 40px は幅の 1/20、高さの 1/15 にあたる。
        #expect(abs(expandedPoints.map(\.x).min()! - 0.15) < 1e-12)
        #expect(abs(expandedPoints.map(\.x).max()! - 0.85) < 1e-12)
        #expect(abs(expandedPoints.map(\.y).min()! - (0.2 - 40.0 / 600)) < 1e-12)
        #expect(RectangularGuideContour().isRectangleLikeContour(expandedPoints))
    }

    @Test func 矩形は単位範囲をはみ出さない() {
        let rectangle = RectangularGuideContour().rectangularContour(
            for: CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
        )

        let expandedPoints = padding.expanded(rectangle, imageSize: imageSize, paddingPixels: 200)

        #expect(expandedPoints.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 })
    }
}
