import CoreGraphics
import Foundation
import Testing
@testable import qool

/// [SubjectMaskExtractorInfrastructure](../qool/Infrastructure/Vision/SubjectMaskExtractorInfrastructure.swift) の検証。
///
/// **Vision の実際の推論を通します。** 移植元と出力を突き合わせる方法が使えないため
/// （モデルの出力を再現できない）、性質と座標系だけを押さえます。
struct SubjectMaskExtractorTests {
    private let extractor = SubjectMaskExtractorInfrastructure()
    private let deriver = MaskContourDeriverInfrastructure()

    /// マスクから輪郭を導く。**抽出器はマスクを返すので、位置を測るには導出が要ります。**
    private func contour(in image: CGImage, guidedBy guide: [CGPoint]) async -> [CGPoint]? {
        guard let mask = await extractor.extractMask(in: image, guidedBy: guide) else {
            return nil
        }

        return deriver.contours(from: mask, threshold: 128).first
    }

    /// 被写体らしい塊を 1 つ置いた画像。`CGContext` は左下原点なので、
    /// `y` を大きく取ると画像の上側に出ます。
    private func makeImage(subjectAtTop: Bool) -> CGImage {
        let size = 512
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        context.setFillColor(CGColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(red: 0.1, green: 0.15, blue: 0.35, alpha: 1))
        context.fillEllipse(in: CGRect(x: 156, y: subjectAtTop ? 300 : 52, width: 200, height: 160))

        return context.makeImage()!
    }

    /// 画面座標（左上原点）で矩形のなぞりを作る。
    private func guide(top: CGFloat, height: CGFloat) -> [CGPoint] {
        var points: [CGPoint] = []
        let steps = 16
        let left: CGFloat = 0.2
        let width: CGFloat = 0.6

        for index in 0..<steps { points.append(CGPoint(x: left + width * CGFloat(index) / CGFloat(steps), y: top)) }
        for index in 0..<steps { points.append(CGPoint(x: left + width, y: top + height * CGFloat(index) / CGFloat(steps))) }
        for index in 0..<steps { points.append(CGPoint(x: left + width - width * CGFloat(index) / CGFloat(steps), y: top + height)) }
        for index in 0..<steps { points.append(CGPoint(x: left, y: top + height - height * CGFloat(index) / CGFloat(steps))) }

        return points
    }

    @Test func 被写体を囲むとマスクが返る() async throws {
        let mask = await extractor.extractMask(
            in: makeImage(subjectAtTop: true),
            guidedBy: guide(top: 0.05, height: 0.45)
        )

        let found = try #require(mask)
        let filled = found.coverage.filter { $0 > 128 }.count

        #expect(filled > 0)
        #expect(filled < found.coverage.count)
    }

    /// **しきい値を掛けずに返すことの確認。** 縁に中間の被覆率が残っていれば、
    /// 半透明を表現できる形になっています。
    @Test func 縁には中間の被覆率が残る() async throws {
        let mask = try #require(
            await extractor.extractMask(
                in: makeImage(subjectAtTop: true),
                guidedBy: guide(top: 0.05, height: 0.45)
            )
        )

        let partial = mask.coverage.filter { $0 > 0 && $0 < 255 }.count

        #expect(partial > 0)
    }

    @Test func 導いた輪郭は正規化座標に収まる() async throws {
        let points = try #require(
            await contour(in: makeImage(subjectAtTop: true), guidedBy: guide(top: 0.05, height: 0.45))
        )
        let outside = points.filter { $0.x < 0 || $0.x > 1 || $0.y < 0 || $0.y > 1 }

        #expect(points.count >= 8)
        #expect(outside.isEmpty)
    }

    /// **なぞりの座標系（左上原点）と Vision の座標系が一致していることの確認。**
    ///
    /// ここが反転していると、上の被写体を囲んだのに何も取れない（あるいはその逆）という
    /// 分かりにくい壊れ方をします。Vision は左下原点の API も多いため、明示的に固定します。
    @Test func なぞりと画像の上下が一致している() async {
        let topImage = makeImage(subjectAtTop: true)
        let upperGuide = guide(top: 0.05, height: 0.45)
        let lowerGuide = guide(top: 0.55, height: 0.4)

        // 上に被写体 → 上をなぞれば取れ、下をなぞれば取れない
        #expect(await extractor.extractMask(in: topImage, guidedBy: upperGuide) != nil)
        #expect(await extractor.extractMask(in: topImage, guidedBy: lowerGuide) == nil)

        // 下に被写体 → 逆になる
        let bottomImage = makeImage(subjectAtTop: false)
        #expect(await extractor.extractMask(in: bottomImage, guidedBy: lowerGuide) != nil)
        #expect(await extractor.extractMask(in: bottomImage, guidedBy: upperGuide) == nil)
    }

    /// 輪郭はなぞりの周辺に収まります。なぞりの内側にある被写体だけを選ぶためです。
    @Test func 輪郭はなぞりの近くに収まる() async throws {
        let guidePoints = guide(top: 0.05, height: 0.45)
        let points = try #require(await contour(in: makeImage(subjectAtTop: true), guidedBy: guidePoints))

        let bounds = ContourGeometry().bounds(for: guidePoints).insetBy(dx: -0.05, dy: -0.05)
        let outside = points.filter { !bounds.contains($0) }

        #expect(outside.isEmpty)
    }

    @Test func 点が少なすぎるなぞりでは何も返さない() async {
        let image = makeImage(subjectAtTop: true)

        #expect(await extractor.extractMask(in: image, guidedBy: []) == nil)
        #expect(await extractor.extractMask(in: image, guidedBy: [CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.6, y: 0.6)]) == nil)
    }

    /// 被写体のない画像では何も返しません。
    @Test func 被写体がなければ何も返さない() async {
        let size = 512
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        #expect(await extractor.extractMask(in: context.makeImage()!, guidedBy: guide(top: 0.2, height: 0.6)) == nil)
    }
}
