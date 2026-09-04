import CoreGraphics

/// 輪郭の見た目を整える。切り抜きの品質はほぼここで決まります。
///
/// StarWindow からの移植（[取り込み計画](../../../docs/image-editing/04-integration-plan.md)）。
/// 座標は正規化（`0...1`）で、ピクセル単位の定数は `referenceResolution` で割って正規化します。
///
/// **角アンカーを保護してから平滑化するのが要点です。** 全体を一様にかけると、
/// 紙の角のような残すべき角まで丸まります。
nonisolated struct ContourSmoother {
    // MARK: - トゲの除去

    static let spikeRemovalIterations = 2
    static let spikeAngleDegrees: CGFloat = 48
    static let spikeDistanceMultiplier: CGFloat = 2.15

    // MARK: - 直線化

    static let isStraighteningEnabled = true
    static let straighteningWindow = 7
    static let straighteningAngleDegrees: CGFloat = 10
    static let straighteningMinimumRun = 30
    static let straighteningStrength: CGFloat = 0.86

    // MARK: - 角の丸め

    static let curveSmoothingIterations = 2
    static let curveSmoothingAmount: CGFloat = 0.24

    // MARK: - 平滑化

    static let smoothingIterations = 3
    static let smoothingStrength: CGFloat = 0.35
    /// これより鋭い曲がり角をアンカー（残すべき角）とみなします。
    static let anchorAngleDegrees: CGFloat = 150
    static let minimumAnchorSpacingPixels: CGFloat = 18
    /// アンカーの前後この距離は平滑化しません。
    static let anchorProtectionPixels: CGFloat = 3
    /// アンカー検出は、元のパスではなくこの間隔で粗く再サンプリングしたパスに対して行います。
    /// 元パスのギザギザを角と誤検出しないためです。
    static let cornerDetectionResamplePixels: CGFloat = 10
    static let minimumSegmentPoints = 8
    /// ピクセル単位の定数を正規化するときの基準解像度。
    static let referenceResolution: CGFloat = 640

    init() {}

    /// 5 段構成。densify → トゲ除去 → 直線化 → 角の丸め → 平滑化。
    func polished(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 8 else {
            return points
        }

        let cleaned = removeSpikes(from: densify(points, maxSegmentLength: 0.012))
        let straightened = straightenLineRuns(cleaned)
        let rounded = roundCorners(straightened)

        return smooth(rounded)
    }

    /// 点列を等間隔に増やす。以降の段が「点の間隔がほぼ一様」を前提にしています。
    func densify(_ points: [CGPoint], maxSegmentLength: CGFloat = 0.018) -> [CGPoint] {
        guard points.count >= 2 else {
            return points
        }

        var result: [CGPoint] = []

        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let distance = hypot(next.x - current.x, next.y - current.y)
            let steps = max(1, Int(ceil(distance / maxSegmentLength)))

            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                result.append(
                    CGPoint(
                        x: current.x + (next.x - current.x) * t,
                        y: current.y + (next.y - current.y) * t
                    )
                )
            }
        }

        return result
    }

    func smooth(_ points: [CGPoint]) -> [CGPoint] {
        guard
            points.count >= 4,
            Self.smoothingIterations > 0,
            Self.smoothingStrength > 0
        else {
            return points
        }

        return smoothClosedByAnchors(points)
    }

    // MARK: - トゲの除去

    /// 隣と鋭角をなす点、または飛び離れた点を、前後の中点へ寄せます。
    private func removeSpikes(from points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 8, Self.spikeRemovalIterations > 0 else {
            return points
        }

        var result = points

        for _ in 0..<Self.spikeRemovalIterations {
            let medianLength = medianSegmentLength(result)
            let maximumDistance = max(0.004, medianLength * Self.spikeDistanceMultiplier)
            let minimumCosine = cos(Self.spikeAngleDegrees * .pi / 180)

            result = result.indices.map { index in
                let previous = result[(index - 1 + result.count) % result.count]
                let current = result[index]
                let next = result[(index + 1) % result.count]
                let previousVector = CGPoint(x: previous.x - current.x, y: previous.y - current.y)
                let nextVector = CGPoint(x: next.x - current.x, y: next.y - current.y)
                let previousLength = hypot(previousVector.x, previousVector.y)
                let nextLength = hypot(nextVector.x, nextVector.y)

                guard previousLength > 0.0001, nextLength > 0.0001 else {
                    return current
                }

                let cosine = (previousVector.x * nextVector.x + previousVector.y * nextVector.y)
                    / (previousLength * nextLength)
                let isSharpPoint = cosine < -minimumCosine
                let isLongJump = previousLength > maximumDistance || nextLength > maximumDistance

                guard isSharpPoint || isLongJump else {
                    return current
                }

                return CGPoint(
                    x: (previous.x + next.x) / 2,
                    y: (previous.y + next.y) / 2
                )
            }
        }

        return result
    }

    private func medianSegmentLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else {
            return 0
        }

        let lengths = points.indices.map { index in
            let current = points[index]
            let next = points[(index + 1) % points.count]
            return hypot(next.x - current.x, next.y - current.y)
        }.sorted()

        return lengths[lengths.count / 2]
    }

    // MARK: - 直線化

    /// ほぼ直線の区間を最小二乗の直線へ寄せます。定規で引いた枠がガタつくのを防ぎます。
    private func straightenLineRuns(_ points: [CGPoint]) -> [CGPoint] {
        guard
            Self.isStraighteningEnabled,
            points.count >= max(8, Self.straighteningMinimumRun)
        else {
            return points
        }

        let halfWindow = max(2, Self.straighteningWindow / 2)
        let maximumAngle = Self.straighteningAngleDegrees * .pi / 180
        let straightFlags = points.indices.map { index in
            isLocallyStraight(points, at: index, halfWindow: halfWindow, maximumAngle: maximumAngle)
        }
        var result = points
        var visited = Array(repeating: false, count: points.count)

        for startIndex in points.indices where straightFlags[startIndex] && !visited[startIndex] {
            let run = straightRun(
                from: startIndex,
                flags: straightFlags,
                visited: &visited
            )

            guard run.count >= Self.straighteningMinimumRun else {
                continue
            }

            let runPoints = run.map { points[$0] }
            let line = bestFitLine(for: runPoints)
            let strength = max(0, min(1, Self.straighteningStrength))

            for index in run {
                let projected = project(points[index], onto: line)
                result[index] = CGPoint(
                    x: points[index].x * (1 - strength) + projected.x * strength,
                    y: points[index].y * (1 - strength) + projected.y * strength
                )
            }
        }

        return result
    }

    private func isLocallyStraight(
        _ points: [CGPoint],
        at index: Int,
        halfWindow: Int,
        maximumAngle: CGFloat
    ) -> Bool {
        let previous = points[(index - halfWindow + points.count) % points.count]
        let current = points[index]
        let next = points[(index + halfWindow) % points.count]
        let incoming = CGPoint(x: current.x - previous.x, y: current.y - previous.y)
        let outgoing = CGPoint(x: next.x - current.x, y: next.y - current.y)
        let incomingLength = hypot(incoming.x, incoming.y)
        let outgoingLength = hypot(outgoing.x, outgoing.y)

        guard incomingLength > 0.0001, outgoingLength > 0.0001 else {
            return false
        }

        let dot = incoming.x * outgoing.x + incoming.y * outgoing.y
        let cosine = max(-1, min(1, dot / (incomingLength * outgoingLength)))
        let angle = acos(cosine)

        return angle <= maximumAngle
    }

    private func straightRun(
        from startIndex: Int,
        flags: [Bool],
        visited: inout [Bool]
    ) -> [Int] {
        let count = flags.count
        var run: [Int] = []
        var index = startIndex

        while flags[index], !visited[index] {
            visited[index] = true
            run.append(index)
            index = (index + 1) % count

            if index == startIndex {
                break
            }
        }

        return run
    }

    private func bestFitLine(for points: [CGPoint]) -> (origin: CGPoint, direction: CGPoint) {
        let center = centroid(of: points)
        var xx: CGFloat = 0
        var xy: CGFloat = 0
        var yy: CGFloat = 0

        for point in points {
            let dx = point.x - center.x
            let dy = point.y - center.y
            xx += dx * dx
            xy += dx * dy
            yy += dy * dy
        }

        let angle = 0.5 * atan2(2 * xy, xx - yy)
        let direction = CGPoint(x: cos(angle), y: sin(angle))

        return (center, direction)
    }

    private func project(
        _ point: CGPoint,
        onto line: (origin: CGPoint, direction: CGPoint)
    ) -> CGPoint {
        let vector = CGPoint(x: point.x - line.origin.x, y: point.y - line.origin.y)
        let amount = vector.x * line.direction.x + vector.y * line.direction.y

        return CGPoint(
            x: line.origin.x + line.direction.x * amount,
            y: line.origin.y + line.direction.y * amount
        )
    }

    private func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else {
            return .zero
        }

        let sum = points.reduce(CGPoint.zero) { partialResult, point in
            CGPoint(x: partialResult.x + point.x, y: partialResult.y + point.y)
        }

        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    // MARK: - 角の丸め

    /// Chaikin 法。各辺を内分した 2 点に置き換えるため、**点数が反復ごとに倍になります。**
    private func roundCorners(_ points: [CGPoint]) -> [CGPoint] {
        guard
            points.count >= 4,
            Self.curveSmoothingIterations > 0,
            Self.curveSmoothingAmount > 0
        else {
            return points
        }

        var result = points
        let amount = max(0, min(0.48, Self.curveSmoothingAmount))

        for _ in 0..<Self.curveSmoothingIterations {
            var rounded: [CGPoint] = []
            rounded.reserveCapacity(result.count * 2)

            for index in result.indices {
                let current = result[index]
                let next = result[(index + 1) % result.count]

                rounded.append(
                    CGPoint(
                        x: current.x * (1 - amount) + next.x * amount,
                        y: current.y * (1 - amount) + next.y * amount
                    )
                )
                rounded.append(
                    CGPoint(
                        x: current.x * amount + next.x * (1 - amount),
                        y: current.y * amount + next.y * (1 - amount)
                    )
                )
            }

            result = rounded
        }

        return result
    }

    // MARK: - アンカーを保護した平滑化

    private func smoothClosedByAnchors(_ points: [CGPoint]) -> [CGPoint] {
        let anchors = importantAnchorIndices(in: points)
        guard anchors.count >= 2 else {
            return smoothOpen(points, preservesEndpoints: false)
        }

        var result = points

        for segment in closedSegments(between: anchors, pointCount: points.count) {
            smoothProtectedSegment(segment, in: &result)
        }

        return result
    }

    private func smoothOpen(_ points: [CGPoint], preservesEndpoints: Bool = true) -> [CGPoint] {
        var result = points
        smoothWholeRun(&result, preservesEndpoints: preservesEndpoints)

        return result
    }

    private func smoothSegment(_ indices: [Int], in points: inout [CGPoint], preservesEndpoints: Bool) {
        guard indices.count >= Self.minimumSegmentPoints else {
            return
        }

        var segmentPoints = indices.map { points[$0] }
        smoothWholeRun(&segmentPoints, preservesEndpoints: preservesEndpoints)

        guard segmentPoints.count == indices.count else {
            return
        }

        for offset in indices.indices {
            points[indices[offset]] = segmentPoints[offset]
        }
    }

    private func smoothProtectedSegment(_ indices: [Int], in points: inout [CGPoint]) {
        let protected = unprotectedCenterIndices(in: indices, points: points)
        smoothSegment(protected, in: &points, preservesEndpoints: true)
    }

    /// 区間の両端から `anchorProtectionPixels` 相当を除いた中央部分を返します。
    /// 保護を除くと残りが短すぎる区間は、平滑化しません（空を返す）。
    private func unprotectedCenterIndices(in indices: [Int], points: [CGPoint]) -> [Int] {
        guard indices.count >= Self.minimumSegmentPoints else {
            return indices
        }

        let protectionDistance = Self.anchorProtectionPixels / Self.referenceResolution
        guard protectionDistance > 0 else {
            return indices
        }

        var startOffset = 0
        var startDistance: CGFloat = 0

        while startOffset < indices.count - 1, startDistance < protectionDistance {
            let current = points[indices[startOffset]]
            let next = points[indices[startOffset + 1]]
            startDistance += hypot(next.x - current.x, next.y - current.y)
            startOffset += 1
        }

        var endOffset = indices.count - 1
        var endDistance: CGFloat = 0

        while endOffset > startOffset, endDistance < protectionDistance {
            let current = points[indices[endOffset]]
            let previous = points[indices[endOffset - 1]]
            endDistance += hypot(current.x - previous.x, current.y - previous.y)
            endOffset -= 1
        }

        guard endOffset - startOffset + 1 >= Self.minimumSegmentPoints else {
            return []
        }

        return Array(indices[startOffset...endOffset])
    }

    private func smoothWholeRun(_ points: inout [CGPoint], preservesEndpoints: Bool) {
        guard
            points.count >= 4,
            Self.smoothingIterations > 0,
            Self.smoothingStrength > 0
        else {
            return
        }

        let strength = max(0, min(1, Self.smoothingStrength))
        let indexRange: Range<Int>

        if preservesEndpoints {
            indexRange = 1..<(points.count - 1)
        } else {
            indexRange = 0..<points.count
        }

        guard !indexRange.isEmpty else {
            return
        }

        for _ in 0..<Self.smoothingIterations {
            let currentPoints = points
            var nextPoints = points

            for index in indexRange {
                let previous: CGPoint
                let next: CGPoint

                if preservesEndpoints {
                    previous = currentPoints[index - 1]
                    next = currentPoints[index + 1]
                } else {
                    previous = currentPoints[(index - 1 + currentPoints.count) % currentPoints.count]
                    next = currentPoints[(index + 1) % currentPoints.count]
                }

                let current = currentPoints[index]
                let average = CGPoint(
                    x: (previous.x + current.x + next.x) / 3,
                    y: (previous.y + current.y + next.y) / 3
                )

                nextPoints[index] = CGPoint(
                    x: current.x * (1 - strength) + average.x * strength,
                    y: current.y * (1 - strength) + average.y * strength
                )
            }

            points = nextPoints
        }
    }

    // MARK: - アンカーの検出

    /// アンカー同士が近すぎる場合は、**より鋭いほうを残します。**
    private func importantAnchorIndices(in points: [CGPoint]) -> [Int] {
        guard points.count >= 3 else {
            return []
        }

        let minimumSpacing = Self.minimumAnchorSpacingPixels / Self.referenceResolution
        let detectionPoints = resampledClosedPoints(
            points,
            spacing: Self.cornerDetectionResamplePixels / Self.referenceResolution
        )
        let sourcePoints = detectionPoints.count >= 3 ? detectionPoints : points
        let candidates = sourcePoints.indices.compactMap { index -> Int? in
            let previous = sourcePoints[(index - 1 + sourcePoints.count) % sourcePoints.count]
            let current = sourcePoints[index]
            let next = sourcePoints[(index + 1) % sourcePoints.count]

            guard angleDegrees(previous: previous, current: current, next: next) <= Self.anchorAngleDegrees else {
                return nil
            }

            return nearestIndex(to: current, in: points)
        }

        guard !candidates.isEmpty else {
            return []
        }

        var anchors: [Int] = []

        for index in candidates {
            if let last = anchors.last,
               contourDistance(from: last, to: index, in: points) < minimumSpacing {
                let lastAngle = angleDegrees(
                    previous: points[(last - 1 + points.count) % points.count],
                    current: points[last],
                    next: points[(last + 1) % points.count]
                )
                let currentAngle = angleDegrees(
                    previous: points[(index - 1 + points.count) % points.count],
                    current: points[index],
                    next: points[(index + 1) % points.count]
                )

                if currentAngle < lastAngle {
                    anchors[anchors.count - 1] = index
                }
            } else {
                anchors.append(index)
            }
        }

        // 閉じたパスなので、末尾と先頭が近すぎる場合も間引きます。
        if anchors.count > 1,
           let first = anchors.first,
           let last = anchors.last,
           contourDistance(from: last, to: first, in: points) < minimumSpacing {
            let firstAngle = angleDegrees(
                previous: points[(first - 1 + points.count) % points.count],
                current: points[first],
                next: points[(first + 1) % points.count]
            )
            let lastAngle = angleDegrees(
                previous: points[(last - 1 + points.count) % points.count],
                current: points[last],
                next: points[(last + 1) % points.count]
            )

            if lastAngle < firstAngle {
                anchors[0] = last
            }

            anchors.removeLast()
        }

        return anchors.sorted()
    }

    private func closedSegments(between anchors: [Int], pointCount: Int) -> [[Int]] {
        guard anchors.count >= 2, pointCount > 0 else {
            return []
        }

        return anchors.indices.map { anchorIndex in
            let start = anchors[anchorIndex]
            let end = anchors[(anchorIndex + 1) % anchors.count]
            var segment = [start]
            var index = start

            while index != end {
                index = (index + 1) % pointCount
                segment.append(index)
            }

            return segment
        }
    }

    /// 輪郭に沿った距離。直線距離ではありません。
    private func contourDistance(from start: Int, to end: Int, in points: [CGPoint]) -> CGFloat {
        guard points.count >= 2, start != end else {
            return 0
        }

        var distance: CGFloat = 0
        var index = start

        while index != end {
            let nextIndex = (index + 1) % points.count
            distance += hypot(points[nextIndex].x - points[index].x, points[nextIndex].y - points[index].y)
            index = nextIndex
        }

        return distance
    }

    private func resampledClosedPoints(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard points.count >= 3, spacing > 0 else {
            return points
        }

        let perimeter = points.indices.reduce(CGFloat(0)) { partialResult, index in
            let current = points[index]
            let next = points[(index + 1) % points.count]
            return partialResult + hypot(next.x - current.x, next.y - current.y)
        }
        let sampleCount = max(3, Int((perimeter / spacing).rounded()))
        let step = perimeter / CGFloat(sampleCount)

        return (0..<sampleCount).compactMap { sampleIndex in
            point(onClosedContour: points, atDistance: CGFloat(sampleIndex) * step)
        }
    }

    private func point(onClosedContour points: [CGPoint], atDistance distance: CGFloat) -> CGPoint? {
        guard points.count >= 2 else {
            return points.first
        }

        var remaining = distance

        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let segmentLength = hypot(next.x - current.x, next.y - current.y)

            guard segmentLength > 0 else {
                continue
            }

            if remaining <= segmentLength {
                let ratio = remaining / segmentLength
                return CGPoint(
                    x: current.x + (next.x - current.x) * ratio,
                    y: current.y + (next.y - current.y) * ratio
                )
            }

            remaining -= segmentLength
        }

        return points.last
    }

    private func nearestIndex(to target: CGPoint, in points: [CGPoint]) -> Int {
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for index in points.indices {
            let point = points[index]
            let distance = hypot(point.x - target.x, point.y - target.y)

            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    /// 3 点がなす角。点が重なっている場合は 180 度（= 曲がっていない）として扱います。
    private func angleDegrees(previous: CGPoint, current: CGPoint, next: CGPoint) -> CGFloat {
        let first = CGPoint(x: previous.x - current.x, y: previous.y - current.y)
        let second = CGPoint(x: next.x - current.x, y: next.y - current.y)
        let firstLength = hypot(first.x, first.y)
        let secondLength = hypot(second.x, second.y)

        guard firstLength > 0.000001, secondLength > 0.000001 else {
            return 180
        }

        let cosine = max(-1, min(1, (first.x * second.x + first.y * second.y) / (firstLength * secondLength)))
        return acos(cosine) * 180 / .pi
    }
}
