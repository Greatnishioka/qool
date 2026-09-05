import CoreGraphics

/// なぞりから輪郭候補を作り、スコア順に並べる。
///
/// **今動く抽出器は矩形補正だけです。** 被写体マスクなどは Vision に依存するため、
/// 順に移植します（[抽出器の一覧](../../../docs/image-editing/02-contour-extractors.md)）。
///
/// 末尾には必ず「手描き」を足します。抽出器が何も出さなくても、
/// なぞった線で切り抜ける状態を保つためです。
nonisolated struct BuildCutoutCandidatesUseCase {
    /// 抽出器の候補に課す面積比の下限。
    private static let extractorMinimumAreaRatio: CGFloat = 0.18

    private let rectangularGuideContour: RectangularGuideContour
    private let selector: ContourCandidateSelector
    private let smoother: ContourSmoother
    private let buildContour: BuildCutoutContourUseCase

    init(
        rectangularGuideContour: RectangularGuideContour = RectangularGuideContour(),
        selector: ContourCandidateSelector = ContourCandidateSelector(),
        smoother: ContourSmoother = ContourSmoother(),
        buildContour: BuildCutoutContourUseCase = BuildCutoutContourUseCase()
    ) {
        self.rectangularGuideContour = rectangularGuideContour
        self.selector = selector
        self.smoother = smoother
        self.buildContour = buildContour
    }

    /// - Parameter tracePoints: 画像の表示矩形を基準にした正規化座標（`0...1`）。
    /// - Returns: 推奨 → スコア降順 → 手描き、の順。なぞりが短ければ空。
    func callAsFunction(tracePoints: [CGPoint]) -> [CutoutCandidate] {
        let handDrawnContours = buildContour(tracePoints: tracePoints)
        guard !handDrawnContours.isEmpty else {
            return []
        }

        let scored = selector.scoredCandidates(from: extract(from: tracePoints), guide: tracePoints)
        let recommendedID = selector.bestCandidate(from: extract(from: tracePoints), guide: tracePoints)?.source

        let extracted = scored
            .sorted { $0.score > $1.score }
            .map { entry in
                CutoutCandidate(
                    source: entry.candidate.source,
                    contours: contours(for: entry.candidate),
                    score: entry.score,
                    isRecommended: entry.candidate.source == recommendedID
                )
            }

        return extracted + [
            CutoutCandidate(
                source: nil,
                contours: handDrawnContours,
                score: nil,
                // 抽出器が推奨を出せなかったときは、手描きが推奨になります。
                isRecommended: recommendedID == nil
            )
        ]
    }

    private func extract(from guide: [CGPoint]) -> [ContourCandidate] {
        guard let rectangularContour = rectangularGuideContour.detectContour(from: guide) else {
            return []
        }

        return [
            ContourCandidate(
                contour: rectangularContour,
                source: .rectangularGuide,
                minimumAreaRatio: Self.extractorMinimumAreaRatio
            )
        ]
    }

    /// 抽出器によっては、表示前に平滑化をかけます。
    /// 矩形はすでに直線的なので、かけると角が丸まります。
    private func contours(for candidate: ContourCandidate) -> [CanvasPathContour] {
        let points = candidate.smoothsContour ? smoother.polished(candidate.contour) : candidate.contour

        return [
            CanvasPathContour(
                points: points.map { NormalizedPoint(x: Double($0.x), y: Double($0.y)) },
                isClosed: true
            )
        ]
    }
}
