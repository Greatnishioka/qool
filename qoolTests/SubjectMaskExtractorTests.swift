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

    @Test func 被写体を囲むと輪郭が返る() async throws {
        let contour = await extractor.extractContour(in: makeImage(subjectAtTop: true), guidedBy: guide(top: 0.05, height: 0.45))

        let points = try #require(contour)
        #expect(points.count >= 8)
        #expect(points.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 })
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
        #expect(await extractor.extractContour(in: topImage, guidedBy: upperGuide) != nil)
        #expect(await extractor.extractContour(in: topImage, guidedBy: lowerGuide) == nil)

        // 下に被写体 → 逆になる
        let bottomImage = makeImage(subjectAtTop: false)
        #expect(await extractor.extractContour(in: bottomImage, guidedBy: lowerGuide) != nil)
        #expect(await extractor.extractContour(in: bottomImage, guidedBy: upperGuide) == nil)
    }

    /// 輪郭はなぞりの周辺に収まります（なぞりの外側 0.05 まで見ます）。
    @Test func 輪郭はなぞりの近くに収まる() async throws {
        let guidePoints = guide(top: 0.05, height: 0.45)
        let contour = try #require(await extractor.extractContour(in: makeImage(subjectAtTop: true), guidedBy: guidePoints))

        let bounds = ContourGeometry().bounds(for: guidePoints).insetBy(dx: -0.05, dy: -0.05)
        #expect(contour.allSatisfy { bounds.contains($0) })
    }

    @Test func 点が少なすぎるなぞりでは何も返さない() async {
        let image = makeImage(subjectAtTop: true)

        #expect(await extractor.extractContour(in: image, guidedBy: []) == nil)
        #expect(await extractor.extractContour(in: image, guidedBy: [CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.6, y: 0.6)]) == nil)
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

        #expect(await extractor.extractContour(in: context.makeImage()!, guidedBy: guide(top: 0.2, height: 0.6)) == nil)
    }
}
