import CoreGraphics

/// なぞりから輪郭候補を作り、スコア順に並べる。
///
/// **今動く抽出器は矩形補正だけです。** 被写体マスクなどは Vision に依存するため、
/// 順に移植します（[抽出器の一覧](../../../docs/image-editing/02-contour-extractors.md)）。
///
/// 末尾には必ず「手描き」を足します。抽出器が何も出さなくても、
/// なぞった線で切り抜ける状態を保つためです。
nonisolated struct BuildCutoutCandidatesUseCase {
    /// 幾何ベースの抽出器（矩形補正・色矩形）に課す面積比の下限。
    private static let guidedMinimumAreaRatio: CGFloat = 0.18
    /// 検出ベースの抽出器（被写体マスクなど）に課す面積比の下限。
    private static let detectionMinimumAreaRatio: CGFloat = 0.55
    /// マスクから輪郭を導くときに「内側」とみなす被覆率。
    /// **表示と採点にだけ効きます。** マスク自体は連続値のまま保存します。
    private static let maskThreshold: UInt8 = 128

    private let rectangularGuideContour: RectangularGuideContour
    private let subjectMaskExtractor: any CutoutMaskExtractorProtocol
    private let grabCutMaskExtractor: any CutoutMaskExtractorProtocol
    private let maskContourDeriver: any MaskContourDeriverProtocol
    private let selector: ContourCandidateSelector
    private let smoother: ContourSmoother
    private let buildContour: BuildCutoutContourUseCase

    init(
        rectangularGuideContour: RectangularGuideContour = RectangularGuideContour(),
        subjectMaskExtractor: any CutoutMaskExtractorProtocol = SubjectMaskExtractorInfrastructure(),
        grabCutMaskExtractor: any CutoutMaskExtractorProtocol = GrabCutContourExtractorInfrastructure(),
        maskContourDeriver: any MaskContourDeriverProtocol = MaskContourDeriverInfrastructure(),
        selector: ContourCandidateSelector = ContourCandidateSelector(),
        smoother: ContourSmoother = ContourSmoother(),
        buildContour: BuildCutoutContourUseCase = BuildCutoutContourUseCase()
    ) {
        self.rectangularGuideContour = rectangularGuideContour
        self.subjectMaskExtractor = subjectMaskExtractor
        self.grabCutMaskExtractor = grabCutMaskExtractor
        self.maskContourDeriver = maskContourDeriver
        self.selector = selector
        self.smoother = smoother
        self.buildContour = buildContour
    }

    /// - Parameter tracePoints: 画像の表示矩形を基準にした正規化座標（`0...1`）。
    /// - Parameter image: 元画像。検出ベースの抽出器が使います。
    /// - Returns: 推奨 → スコア降順 → 抽出順 → 手描き、の順。なぞりが短ければ空。
    func callAsFunction(image: CGImage, tracePoints: [CGPoint]) async -> [CutoutCandidate] {
        let handDrawnContours = buildContour(tracePoints: tracePoints)
        guard !handDrawnContours.isEmpty else {
            return []
        }

        let extracted = await extract(in: image, from: tracePoints)
        let scored = selector.scoredCandidates(from: extracted, guide: tracePoints)
        let scoreBySource = Dictionary(
            scored.map { ($0.candidate.source, $0.score) },
            uniquingKeysWith: { first, _ in first }
        )
        let recommendedSource = scored
            .filter { $0.score >= ContourCandidateSelector.minimumAutoScore }
            .max { first, second in first.score < second.score }?
            .candidate
            .source

        // **足切りされた候補も残します。** 自動で選ばれなかっただけで、
        // 手で選べば使えます。スコアは `nil` になり、末尾側へ並びます。
        let displayed = extracted
            .enumerated()
            .map { index, candidate in
                (
                    index: index,
                    candidate: CutoutCandidate(
                        source: candidate.source,
                        contours: contours(for: candidate),
                        mask: candidate.mask,
                        score: scoreBySource[candidate.source],
                        isRecommended: candidate.source == recommendedSource
                    )
                )
            }
            .sorted(by: isOrderedBefore)
            .map(\.candidate)

        return displayed + [
            CutoutCandidate(
                source: nil,
                contours: handDrawnContours,
                score: nil,
                // 抽出器が推奨を出せなかったときは、手描きが推奨になります。
                isRecommended: recommendedSource == nil
            )
        ]
    }

    /// 推奨 → スコア降順（スコアなしは後ろ）→ 抽出順。
    ///
    /// 最後に抽出順で決めるのは、**同点の並びを固定するため**です。
    /// Swift の `sorted` は安定ソートを保証しません。
    private func isOrderedBefore(
        _ first: (index: Int, candidate: CutoutCandidate),
        _ second: (index: Int, candidate: CutoutCandidate)
    ) -> Bool {
        if first.candidate.isRecommended != second.candidate.isRecommended {
            return first.candidate.isRecommended
        }

        switch (first.candidate.score, second.candidate.score) {
        case let (firstScore?, secondScore?):
            if firstScore != secondScore {
                return firstScore > secondScore
            }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }

        return first.index < second.index
    }

    /// 抽出器を順に走らせる。**移植済みのものだけ**が並びます。
    private func extract(in image: CGImage, from guide: [CGPoint]) async -> [ContourCandidate] {
        var candidates: [ContourCandidate] = []

        if let subject = await maskCandidate(
            from: subjectMaskExtractor,
            in: image,
            guidedBy: guide,
            source: .subjectMask
        ) {
            candidates.append(subject)
        }

        if let grabCut = await maskCandidate(
            from: grabCutMaskExtractor,
            in: image,
            guidedBy: guide,
            source: .grabCut
        ) {
            candidates.append(grabCut)
        }

        if let rectangularContour = rectangularGuideContour.detectContour(from: guide) {
            candidates.append(
                ContourCandidate(
                    contour: rectangularContour,
                    source: .rectangularGuide,
                    minimumAreaRatio: Self.guidedMinimumAreaRatio
                )
            )
        }

        return candidates
    }

    /// マスクを返す抽出器から候補を作る。
    ///
    /// **輪郭はマスクから導出します。** プレビューの破線と採点は輪郭を前提にしているためで、
    /// 切り抜きの正はマスクのままです。輪郭にできなければ候補として出しません
    /// （採点も表示もできないため）。
    private func maskCandidate(
        from extractor: any CutoutMaskExtractorProtocol,
        in image: CGImage,
        guidedBy guide: [CGPoint],
        source: ContourCandidateSource
    ) async -> ContourCandidate? {
        guard let mask = await extractor.extractMask(in: image, guidedBy: guide),
              let contour = maskContourDeriver.contours(from: mask, threshold: Self.maskThreshold).first else {
            return nil
        }

        return ContourCandidate(
            contour: contour,
            mask: mask,
            source: source,
            minimumAreaRatio: Self.detectionMinimumAreaRatio
        )
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
