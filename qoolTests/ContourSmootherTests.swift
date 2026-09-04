import CoreGraphics
import Foundation
import Testing
@testable import qool

/// [ContourSmoother](../qool/Domain/Services/ContourSmoother.swift) の検証。
///
/// 移植元の StarWindow にテストはありません。**移植時に、同じ入力に対する出力が
/// 移植元と 12 桁まで一致することを確認済み**なので、ここで押さえるのは
/// 「この挙動が今後変わったら気づける」ようにするための性質です。
struct ContourSmootherTests {
    private let smoother = ContourSmoother()

    private func circle(radius: CGFloat, count: Int = 80) -> [CGPoint] {
        (0..<count).map { index in
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
            return CGPoint(x: 0.5 + cos(angle) * radius, y: 0.5 + sin(angle) * radius)
        }
    }

    /// 決定的な擬似ノイズ。実際の写真から取れる輪郭はこの程度にはガタついています。
    private func noisy(_ points: [CGPoint], amplitude: CGFloat) -> [CGPoint] {
        points.enumerated().map { index, point in
            let k = CGFloat(index)
            return CGPoint(
                x: point.x + sin(k * 12.9898) * amplitude,
                y: point.y + sin(k * 78.233) * amplitude
            )
        }
    }

    private func radii(_ points: [CGPoint]) -> [CGFloat] {
        points.map { hypot($0.x - 0.5, $0.y - 0.5) }
    }

    // MARK: - densify

    @Test func densifyは最大セグメント長を超えない() {
        let densified = smoother.densify(circle(radius: 0.3, count: 8), maxSegmentLength: 0.02)

        let lengths = densified.indices.map { index -> CGFloat in
            let current = densified[index]
            let next = densified[(index + 1) % densified.count]
            return hypot(next.x - current.x, next.y - current.y)
        }

        #expect(lengths.max()! <= 0.02 + 1e-9)
        #expect(densified.count > 8)
    }

    @Test func densifyは2点未満をそのまま返す() {
        let single = [CGPoint(x: 0.1, y: 0.2)]

        #expect(smoother.densify(single) == single)
        #expect(smoother.densify([]) == [])
    }

    // MARK: - polished

    /// 8 点未満は形が定まらないため触りません。
    @Test func polishedは8点未満をそのまま返す() {
        let few = circle(radius: 0.3, count: 7)

        #expect(smoother.polished(few) == few)
    }

    /// **この移植の主目的。** 全体を一様に平滑化すると紙の角が丸まります。
    @Test func polishedは矩形の角を残す() {
        let rectangle = RectangularGuideContour().rectangularContour(
            for: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        )

        let polished = smoother.polished(rectangle)

        let corners = [
            CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.2),
            CGPoint(x: 0.8, y: 0.8), CGPoint(x: 0.2, y: 0.8)
        ]
        for corner in corners {
            let distance = polished.map { hypot($0.x - corner.x, $0.y - corner.y) }.min()!
            #expect(distance < 0.01, "角 \(corner) が \(distance) まで丸まった")
        }
    }

    @Test func polishedは矩形の外形を保つ() {
        let rectangle = RectangularGuideContour().rectangularContour(
            for: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        )

        let polished = smoother.polished(rectangle)

        #expect(abs(polished.map(\.x).min()! - 0.2) < 0.001)
        #expect(abs(polished.map(\.x).max()! - 0.8) < 0.001)
        #expect(abs(polished.map(\.y).min()! - 0.2) < 0.001)
        #expect(abs(polished.map(\.y).max()! - 0.8) < 0.001)
    }

    /// 実際に扱うのはこちら。ガタついた輪郭は形を保ったまま整えられます。
    @Test func polishedはノイズのある輪郭の形を保つ() {
        let polished = smoother.polished(noisy(circle(radius: 0.3), amplitude: 0.02))

        let radii = radii(polished)
        #expect(radii.min()! > 0.26)
        #expect(radii.max()! < 0.34)
    }

    @Test func polishedの出力は有限値だけを含む() {
        let polished = smoother.polished(noisy(circle(radius: 0.3), amplitude: 0.02))

        #expect(polished.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    // MARK: - 移植で判明した挙動

    /// **大きな真円は直線化に巻き込まれて潰れます。**
    ///
    /// `densify` 後の点間隔で 3 点ぶんの曲がりが 10 度未満になると、その区間は
    /// 「直線」と判定されます。半径が大きいほど曲がりは緩いので、円周全体が
    /// 1 本の直線区間として最小二乗直線へ 0.86 の強さで寄せられます。
    ///
    /// 移植元と同じ挙動です。実際の輪郭はノイズがあり判定を通らないため実害は出ていませんが、
    /// **解析的に滑らかな輪郭（楕円フィットなど）を渡すと壊れます。**
    @Test func 半径が小さい真円は保たれる() {
        let polished = smoother.polished(circle(radius: 0.15))

        #expect(radii(polished).min()! > 0.14)
    }

    @Test func 半径が大きい真円は直線化で潰れる() {
        let polished = smoother.polished(circle(radius: 0.18))

        // 中心付近まで引き寄せられる。上の 0.15 との差はわずかだが結果は大きく変わる。
        #expect(radii(polished).min()! < 0.05)
    }

    /// **`polished` はトゲを落としません。**
    ///
    /// トゲ除去は「隣との距離が中央値の 2.15 倍を超える点」を対象にしますが、
    /// `polished` は先に `densify` を通すため、トゲへ伸びる長い辺が分割されて
    /// 長さの条件に掛からなくなります。移植元と同じ挙動です。
    @Test func polishedはトゲを落とさない() {
        var spiked = circle(radius: 0.25)
        let angle = CGFloat(10) / 80 * 2 * .pi
        spiked[10] = CGPoint(x: 0.5 + cos(angle) * 0.5, y: 0.5 + sin(angle) * 0.5)

        let polished = smoother.polished(spiked)

        #expect(radii(polished).max()! > 0.49)
    }

    // MARK: - smooth

    @Test func smoothは4点未満をそのまま返す() {
        let few = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1)]

        #expect(smoother.smooth(few) == few)
    }

    @Test func smoothは点数を変えない() {
        let points = noisy(circle(radius: 0.25, count: 40), amplitude: 0.015)

        #expect(smoother.smooth(points).count == points.count)
    }
}
