import CoreGraphics
import Foundation
import Testing
@testable import qool

/// `grabCut` による輪郭抽出の検証。
///
/// **合成画像で測ります。** 実写は目視でしか判定できませんが、
/// 「明るい背景の中の暗い四角」のように答えが分かる画像なら、
/// 抽出が壊れていないことを機械的に固定できます。
struct GrabCutContourExtractorTests {
    private let extractor = GrabCutContourExtractorInfrastructure()
    private let geometry = ContourGeometry()

    /// 白地の中央に黒い四角を描いた画像。四角は `0.3`〜`0.7` を占めます。
    private func imageWithDarkSquare(size: Int = 200) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )

        guard let context else {
            return nil
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1))
        context.fill(
            CGRect(
                x: Double(size) * 0.3,
                y: Double(size) * 0.3,
                width: Double(size) * 0.4,
                height: Double(size) * 0.4
            )
        )

        return context.makeImage()
    }

    /// 四角を大きめに囲んだなぞり。**わざと緩く囲みます。**
    /// なぞりどおりではなく被写体に沿うことを確かめたいためです。
    private func looseGuide() -> [CGPoint] {
        [
            CGPoint(x: 0.15, y: 0.15),
            CGPoint(x: 0.85, y: 0.15),
            CGPoint(x: 0.85, y: 0.85),
            CGPoint(x: 0.15, y: 0.85)
        ]
    }

    @Test func なぞりが足りなければ抽出しない() async throws {
        let image = try #require(imageWithDarkSquare())

        #expect(await extractor.extractContour(in: image, guidedBy: []) == nil)
        #expect(
            await extractor.extractContour(
                in: image,
                guidedBy: [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.8)]
            ) == nil
        )
    }

    /// **なぞりではなく被写体に沿うことの確認。**
    /// なぞりは `0.15`〜`0.85` だが、四角は `0.3`〜`0.7` にある。
    @Test func 緩く囲んでも被写体の縁に寄る() async throws {
        let image = try #require(imageWithDarkSquare())

        let contour = try #require(await extractor.extractContour(in: image, guidedBy: looseGuide()))
        let bounds = geometry.bounds(for: contour)

        #expect(abs(bounds.minX - 0.3) < 0.05)
        #expect(abs(bounds.minY - 0.3) < 0.05)
        #expect(abs(bounds.width - 0.4) < 0.05)
        #expect(abs(bounds.height - 0.4) < 0.05)
    }

    @Test func 輪郭は正規化座標に収まる() async throws {
        let image = try #require(imageWithDarkSquare())

        let contour = try #require(await extractor.extractContour(in: image, guidedBy: looseGuide()))

        #expect(contour.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }
}
