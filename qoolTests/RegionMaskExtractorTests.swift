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

    /// 上から白 20%、黒 30%、白 50% の帯を重ねた画像。
    ///
    /// **上下で帯の幅を変えています。** 対称な絵だと、押す場所と結果の両方が
    /// 裏返っても同じ答えになり、上下の入れ替わりを見つけられません。
    private func imageWithUnevenBands(size: Int = 200) -> CGImage? {
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
        // **`CGContext` は左下原点です。** ここを塗ると、上から 20%〜50% が黒くなります。
        context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1))
        context.fill(CGRect(x: 0, y: length * 0.5, width: length, height: length * 0.3))

        return context.makeImage()
    }

    /// **押す場所も結果も上下が入れ替わらないことの確認。**
    /// 正規化座標は左上原点で、`CGImage` の 1 行目は上です。
    @Test func 押した場所の上下が入れ替わらない() async throws {
        let image = try #require(imageWithUnevenBands())

        // 上から 10% は白い帯の中。広がるのは上の 20% だけです。
        let mask = try #require(
            await extractor.regionMask(in: image, at: CGPoint(x: 0.5, y: 0.1), tolerance: 24)
        )

        let pressed = mask.value(at: CGPoint(x: 0.5, y: 0.1))
        let middle = mask.value(at: CGPoint(x: 0.5, y: 0.3))
        // 裏返っていれば、下の広い白帯（50%）が選ばれて上半分が埋まります。
        let lower = mask.value(at: CGPoint(x: 0.5, y: 0.4))
        let bottom = mask.value(at: CGPoint(x: 0.5, y: 0.9))

        #expect(pressed == 255)
        #expect(middle == 0)
        #expect(lower == 0)
        #expect(bottom == 0)
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
