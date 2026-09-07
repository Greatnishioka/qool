import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 輪郭候補の生成と並び（[BuildCutoutCandidatesUseCase](../qool/Application/UseCases/Image/BuildCutoutCandidatesUseCase.swift)）の検証。
struct CutoutCandidateTests {
    /// 被写体を見つけない抽出器。**Vision を通さないことで、幾何側の挙動だけを見ます。**
    private struct NoSubjectExtractor: SubjectContourExtractorProtocol {
        func extractContour(in image: CGImage, guidedBy guide: [CGPoint]) async -> [CGPoint]? { nil }
    }

    /// 決まった輪郭を返す抽出器。被写体マスクが載ったときの並びを確かめます。
    private struct FixedSubjectExtractor: SubjectContourExtractorProtocol {
        let contour: [CGPoint]

        func extractContour(in image: CGImage, guidedBy guide: [CGPoint]) async -> [CGPoint]? { contour }
    }

    private let buildCandidates = BuildCutoutCandidatesUseCase(subjectContourExtractor: NoSubjectExtractor())

    /// スタブは画像を見ないので、中身は何でも構いません。
    private let dummyImage: CGImage = {
        let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }()

    private func rectTrace(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, steps: Int = 20) -> [CGPoint] {
        var points: [CGPoint] = []
        for index in 0..<steps { points.append(CGPoint(x: x + w * CGFloat(index) / CGFloat(steps), y: y)) }
        for index in 0..<steps { points.append(CGPoint(x: x + w, y: y + h * CGFloat(index) / CGFloat(steps))) }
        for index in 0..<steps { points.append(CGPoint(x: x + w - w * CGFloat(index) / CGFloat(steps), y: y + h)) }
        for index in 0..<steps { points.append(CGPoint(x: x, y: y + h - h * CGFloat(index) / CGFloat(steps))) }
        return points
    }

    private func circleTrace(radius: CGFloat, count: Int = 60) -> [CGPoint] {
        (0..<count).map { index in
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
            return CGPoint(x: 0.5 + cos(angle) * radius, y: 0.5 + sin(angle) * radius)
        }
    }

    /// 抽出器が何も出さなくても、なぞった線で切り抜ける状態を保ちます。
    @Test func 手描き候補は必ず末尾にある() async {
        let candidates = await buildCandidates(image: dummyImage, tracePoints: circleTrace(radius: 0.3))

        #expect(candidates.last?.source == nil)
        #expect(candidates.last?.displayName == "手描き")
        #expect(candidates.last?.score == nil)
    }

    /// 円のなぞりでは矩形補正が輪郭を作らないため、候補は手描きだけになります。
    @Test func 円のなぞりでは候補は手描きだけ() async {
        let candidates = await buildCandidates(image: dummyImage, tracePoints: circleTrace(radius: 0.3))

        #expect(candidates.count == 1)
        #expect(candidates[0].source == nil)
    }

    /// **矩形補正は輪郭としては作られますが、スコアリングを通れません。**
    ///
    /// `RectangularGuideContour.detectContour` はガイドの bounds を矩形にして返すため、
    /// **できあがる輪郭は必ずガイドを包み込みます。** 一方スコアリングの `inside`
    /// （候補の点がガイド内部にある割合、下限 0.58）は包み込む形を想定していません。
    /// 揺れのある実際のなぞりでは 0.0 になります。
    ///
    /// 移植元と同じ挙動です（スコアリングの出力は 170 ケースで一致を確認済み）。
    /// 被写体マスクのようにガイドより内側へ収まる抽出器は、この足切りを通ります。
    @Test func 矩形補正は輪郭になるがスコアリングで落ちる() async throws {
        let guide = rectTrace(0.2, 0.2, 0.6, 0.6)

        let contour = try #require(RectangularGuideContour().detectContour(from: guide))
        #expect(contour.count >= 8)

        let scored = ContourCandidateSelector().scoredCandidates(
            from: [ContourCandidate(contour: contour, source: .rectangularGuide, minimumAreaRatio: 0.18)],
            guide: guide
        )
        #expect(scored.isEmpty)
    }

    /// **足切りされた候補も一覧に残します。** 自動で選ばれなかっただけで、手で選べば使えます。
    /// 消してしまうと「自動が外れても人間が選べる」という前提が崩れます。
    @Test func 足切りされた候補もスコアなしで一覧に残る() async throws {
        let candidates = await buildCandidates(image: dummyImage, tracePoints: rectTrace(0.2, 0.2, 0.6, 0.6))

        let rectangular = try #require(candidates.first { $0.source == .rectangularGuide })
        #expect(rectangular.score == nil)
        #expect(rectangular.isRecommended == false)
        #expect(rectangular.contours.isEmpty == false)
    }

    /// スコアの付いた候補が先、付かない候補が後、手描きは最後です。
    @Test func スコアのない候補は後ろへ並ぶ() async {
        let candidates = await buildCandidates(image: dummyImage, tracePoints: rectTrace(0.2, 0.2, 0.6, 0.6))

        #expect(candidates.count == 2)
        #expect(candidates[0].source == .rectangularGuide)
        #expect(candidates[1].source == nil)
    }

    /// 推奨は常に1つだけです。
    @Test func 推奨はちょうど1つ() async {
        for trace in [rectTrace(0.2, 0.2, 0.6, 0.6), circleTrace(radius: 0.3)] {
            let candidates = await buildCandidates(image: dummyImage, tracePoints: trace)

            #expect(candidates.count { $0.isRecommended } == 1)
        }
    }

    /// 抽出器が推奨を出せなければ、手描きが推奨になります。
    @Test func 抽出器がなければ手描きが推奨になる() async {
        let candidates = await buildCandidates(image: dummyImage, tracePoints: circleTrace(radius: 0.3))

        #expect(candidates.first { $0.isRecommended }?.source == nil)
    }

    @Test func なぞりが短すぎれば候補は空() async {
        #expect(await buildCandidates(image: dummyImage, tracePoints: []).isEmpty)
        #expect(await buildCandidates(image: dummyImage, tracePoints: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.2)]).isEmpty)
    }

    /// 矩形補正は平滑化をかけないため、角がそのまま残ります。
    @Test func 矩形補正の候補は角が保たれる() async throws {
        let candidates = await buildCandidates(image: dummyImage, tracePoints: rectTrace(0.2, 0.2, 0.6, 0.6))
        let rectangular = try #require(candidates.first { $0.source == .rectangularGuide })
        let points = try #require(rectangular.contours.first?.points)

        for corner in [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.8)] {
            let distance = points.map { hypot($0.x - corner.x, $0.y - corner.y) }.min() ?? 1
            #expect(distance < 0.01)
        }
    }

    /// 矩形と色矩形は平滑化をかけません。すでに直線的で、かけると角が丸まります。
    @Test func 矩形系の抽出器だけ平滑化をかけない() async {
        #expect(ContourCandidateSource.rectangularGuide.smoothsContour == false)
        #expect(ContourCandidateSource.coloredRectangle.smoothsContour == false)
        #expect(ContourCandidateSource.subjectMask.smoothsContour)
    }

    @Test func 候補の輪郭は正規化座標に収まる() async {
        for trace in [rectTrace(0.2, 0.2, 0.6, 0.6), circleTrace(radius: 0.3)] {
            for candidate in await buildCandidates(image: dummyImage, tracePoints: trace) {
                for contour in candidate.contours {
                    #expect(contour.points.allSatisfy { $0.x >= -0.001 && $0.x <= 1.001 })
                    #expect(contour.points.allSatisfy { $0.y >= -0.001 && $0.y <= 1.001 })
                }
            }
        }
    }

    /// ガイドより内側に収まる候補は足切りを通ります（被写体マスクが該当します）。
    @Test func ガイドの内側に収まる候補はスコアが付く() async throws {
        let guide = rectTrace(0.2, 0.2, 0.6, 0.6)
        let inner = rectTrace(0.3, 0.3, 0.4, 0.4)

        let scored = ContourCandidateSelector().scoredCandidates(
            from: [ContourCandidate(contour: inner, source: .subjectMask, minimumAreaRatio: 0.18)],
            guide: guide
        )

        #expect(scored.count == 1)
        #expect(try #require(scored.first).score > 0)
    }

    /// 被写体マスクが取れたときは、それが推奨になります（bias +0.55）。
    @Test func 被写体マスクが取れれば推奨になる() async throws {
        let guide = rectTrace(0.2, 0.2, 0.6, 0.6)
        // 検出ベースの抽出器には面積比 0.55 以上が要ります（0.5*0.5 / 0.6*0.6 = 0.69）。
        let build = BuildCutoutCandidatesUseCase(
            subjectContourExtractor: FixedSubjectExtractor(contour: rectTrace(0.25, 0.25, 0.5, 0.5))
        )

        let candidates = await build(image: dummyImage, tracePoints: guide)

        let subject = try #require(candidates.first { $0.source == .subjectMask })
        #expect(subject.isRecommended)
        #expect(subject.score != nil)
        #expect(candidates.first?.source == .subjectMask)
    }

    /// 被写体マスクは平滑化をかけて表示します。
    @Test func 被写体マスクの候補は平滑化される() async throws {
        let rough = rectTrace(0.3, 0.3, 0.4, 0.4, steps: 6)
        let build = BuildCutoutCandidatesUseCase(subjectContourExtractor: FixedSubjectExtractor(contour: rough))

        let candidates = await build(image: dummyImage, tracePoints: rectTrace(0.2, 0.2, 0.6, 0.6))

        let subject = try #require(candidates.first { $0.source == .subjectMask })
        // 平滑化は densify を含むため、点が増えます。
        #expect(try #require(subject.contours.first).points.count > rough.count)
    }
}
