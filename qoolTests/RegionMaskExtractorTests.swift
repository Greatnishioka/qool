import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 押した場所から色の近い範囲を広げる処理の検証。
struct RegionMaskExtractorTests {
    private let extractor = RegionFillExtractorInfrastructure()

    /// 白地の中に、黒い枠で囲まれた白い穴を持つ形を描いた画像。
    /// **カップの取っ手の内側を模しています。**
    private func imageWithEnclosedHole(size: Int = 200) -> CGImage? {
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

        let length = Double(size)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: length, height: length))
        // 黒い塊
        context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1))
        context.fill(CGRect(x: length * 0.2, y: length * 0.2, width: length * 0.6, height: length * 0.6))
        // その内側を白で抜く（囲まれた穴）
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: length * 0.35, y: length * 0.35, width: length * 0.3, height: length * 0.3))

        return context.makeImage()
    }

    private func filledCount(_ mask: CutoutMask) -> Int {
        var count = 0

        for coverage in mask.coverage where coverage > 0 {
            count += 1
        }

        return count
    }

    /// **囲まれた領域だけが選ばれることの確認。** これがブラシとの違いです。
    @Test func 囲まれた内側を押すとその範囲だけ広がる() async throws {
        let image = try #require(imageWithEnclosedHole())

        let mask = try #require(
            await extractor.regionMask(in: image, at: CGPoint(x: 0.5, y: 0.5), tolerance: 24)
        )

        // 内側の白（画像の 9%）だけが選ばれ、外側の白へは漏れません。
        let ratio = Double(filledCount(mask)) / Double(mask.width * mask.height)

        #expect(ratio > 0.05)
        #expect(ratio < 0.2)
        #expect(mask.value(at: CGPoint(x: 0.5, y: 0.5)) == 255)
        // 外側の白は選ばれていません。
        #expect(mask.value(at: CGPoint(x: 0.05, y: 0.05)) == 0)
    }

    @Test func 外側を押すと外側だけが広がる() async throws {
        let image = try #require(imageWithEnclosedHole())

        let mask = try #require(
            await extractor.regionMask(in: image, at: CGPoint(x: 0.05, y: 0.05), tolerance: 24)
        )

        #expect(mask.value(at: CGPoint(x: 0.05, y: 0.05)) == 255)
        // 囲まれた内側までは届きません。
        #expect(mask.value(at: CGPoint(x: 0.5, y: 0.5)) == 0)
    }

    /// 許容差を上げると、黒い枠を越えて広がります。
    @Test func 許容差を上げると広がる範囲が増える() async throws {
        let image = try #require(imageWithEnclosedHole())

        let narrow = try #require(
            await extractor.regionMask(in: image, at: CGPoint(x: 0.5, y: 0.5), tolerance: 8)
        )
        let wide = try #require(
            await extractor.regionMask(in: image, at: CGPoint(x: 0.5, y: 0.5), tolerance: 255)
        )

        #expect(filledCount(wide) > filledCount(narrow))
    }

    @Test func 画像の外を押しても広げない() async throws {
        let image = try #require(imageWithEnclosedHole())

        #expect(await extractor.regionMask(in: image, at: CGPoint(x: 1.5, y: 0.5), tolerance: 24) == nil)
        #expect(await extractor.regionMask(in: image, at: CGPoint(x: -0.1, y: 0.5), tolerance: 24) == nil)
    }
}
