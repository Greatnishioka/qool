import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 輪郭候補の生成と並び（[BuildCutoutCandidatesUseCase](../qool/Application/UseCases/Image/BuildCutoutCandidatesUseCase.swift)）の検証。
struct CutoutCandidateTests {
    private let buildCandidates = BuildCutoutCandidatesUseCase()

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
    @Test func 手描き候補は必ず末尾にある() {
        let candidates = buildCandidates(tracePoints: circleTrace(radius: 0.3))

        #expect(candidates.last?.source == nil)
        #expect(candidates.last?.displayName == "手描き")
        #expect(candidates.last?.score == nil)
    }

    @Test func 円のなぞりでは候補は手描きだけ() {
        let candidates = buildCandidates(tracePoints: circleTrace(radius: 0.3))

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
    @Test func 矩形補正は輪郭になるがスコアリングで落ちる() throws {
        let guide = rectTrace(0.2, 0.2, 0.6, 0.6)

        let contour = try #require(RectangularGuideContour().detectContour(from: guide))
        #expect(contour.count >= 8)

        let scored = ContourCandidateSelector().scoredCandidates(
            from: [ContourCandidate(contour: contour, source: .rectangularGuide, minimumAreaRatio: 0.18)],
            guide: guide
        )
        #expect(scored.isEmpty)

        // 結果として、四角くなぞっても候補は手描きだけになります。
        #expect(buildCandidates(tracePoints: guide).map(\.source) == [nil])
    }

    /// 推奨は常に1つだけです。
    @Test func 推奨はちょうど1つ() {
        for trace in [rectTrace(0.2, 0.2, 0.6, 0.6), circleTrace(radius: 0.3)] {
            let candidates = buildCandidates(tracePoints: trace)

            #expect(candidates.count { $0.isRecommended } == 1)
        }
    }

    /// 抽出器が推奨を出せなければ、手描きが推奨になります。
    @Test func 抽出器がなければ手描きが推奨になる() {
        let candidates = buildCandidates(tracePoints: circleTrace(radius: 0.3))

        #expect(candidates.first { $0.isRecommended }?.source == nil)
    }

    @Test func なぞりが短すぎれば候補は空() {
        #expect(buildCandidates(tracePoints: []).isEmpty)
        #expect(buildCandidates(tracePoints: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.2)]).isEmpty)
    }

    /// 矩形と色矩形は平滑化をかけません。すでに直線的で、かけると角が丸まります。
    @Test func 矩形系の抽出器だけ平滑化をかけない() {
        #expect(ContourCandidateSource.rectangularGuide.smoothsContour == false)
        #expect(ContourCandidateSource.coloredRectangle.smoothsContour == false)
        #expect(ContourCandidateSource.subjectMask.smoothsContour)
    }

    @Test func 候補の輪郭は正規化座標に収まる() {
        for trace in [rectTrace(0.2, 0.2, 0.6, 0.6), circleTrace(radius: 0.3)] {
            for candidate in buildCandidates(tracePoints: trace) {
                for contour in candidate.contours {
                    #expect(contour.points.allSatisfy { $0.x >= -0.001 && $0.x <= 1.001 })
                    #expect(contour.points.allSatisfy { $0.y >= -0.001 && $0.y <= 1.001 })
                }
            }
        }
    }

    /// ガイドより内側に収まる候補は足切りを通ります（被写体マスクが該当します）。
    @Test func ガイドの内側に収まる候補はスコアが付く() throws {
        let guide = rectTrace(0.2, 0.2, 0.6, 0.6)
        let inner = rectTrace(0.3, 0.3, 0.4, 0.4)

        let scored = ContourCandidateSelector().scoredCandidates(
            from: [ContourCandidate(contour: inner, source: .subjectMask, minimumAreaRatio: 0.18)],
            guide: guide
        )

        #expect(scored.count == 1)
        #expect(try #require(scored.first).score > 0)
    }
}
