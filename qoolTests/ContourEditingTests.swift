import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 切り抜きの手直し（第 4 段階 9）の検証。
struct ContourEditingTests {
    private let edit = EditCutoutContourUseCase()
    private let brush = BrushStrokeOutline()
    private let geometry = ContourGeometry()

    private func square(_ x: Double, _ y: Double, _ side: Double) -> [CGPoint] {
        [
            CGPoint(x: x, y: y),
            CGPoint(x: x + side, y: y),
            CGPoint(x: x + side, y: y + side),
            CGPoint(x: x, y: y + side)
        ]
    }

    private func contour(_ points: [CGPoint]) -> CanvasPathContour {
        CanvasPathContour(points: points.map { NormalizedPoint(x: Double($0.x), y: Double($0.y)) })
    }

    private func totalArea(_ contours: [CanvasPathContour]) -> CGFloat {
        contours.reduce(0) { total, contour in
            total + geometry.polygonArea(contour.points.map { CGPoint(x: $0.x, y: $0.y) })
        }
    }

    // MARK: - 正規化座標での精度

    /// **これが前提です。** 輪郭は 0〜1 で持つので、その範囲で合成が壊れないことを最初に確かめます。
    @Test func 正規化座標のまま合成できる() {
        let result = edit(
            [contour(square(0.1, 0.1, 0.4))],
            combining: [square(0.3, 0.1, 0.4)],
            mode: .add
        )

        #expect(result.count == 1)
        // 0.4 四方が 2 つ、0.2 幅で重なる。合計 0.16 * 2 - 0.08 = 0.24。
        #expect(abs(totalArea(result) - 0.24) < 0.001)
    }

    /// 細いブラシでも潰れないこと。格子に落とす方式ならここで解像度の限界に当たります。
    @Test func 細いなぞりでも面積を保つ() {
        let radius: CGFloat = 0.002
        let polygons = brush.polygons(
            for: [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.8, y: 0.5)],
            radius: radius
        )
        let result = edit([], combining: polygons, mode: .add)

        #expect(!result.isEmpty)
        // 長さ 0.6 × 幅 0.004 の帯 + 両端の半円。おおよそ 0.0024。
        #expect(totalArea(result) > 0.002)
    }

    // MARK: - 足す / 引く

    @Test func ペンで足すと広がる() {
        let original = [contour(square(0.3, 0.3, 0.4))]
        let result = edit(original, combining: [square(0.6, 0.3, 0.2)], mode: .add)

        #expect(totalArea(result) > totalArea(original))
    }

    @Test func 消しゴムで引くと狭まる() {
        let original = [contour(square(0.3, 0.3, 0.4))]
        let result = edit(original, combining: [square(0.3, 0.3, 0.2)], mode: .subtract)

        #expect(abs(totalArea(result) - (0.16 - 0.04)) < 0.001)
    }

    /// 真ん中だけ消すと、外周と穴の 2 本になります。描画は `eoFill` なので穴として出ます。
    @Test func 内側を消すと穴が空く() {
        let result = edit(
            [contour(square(0.2, 0.2, 0.6))],
            combining: [square(0.4, 0.4, 0.2)],
            mode: .subtract
        )

        #expect(result.count == 2)
    }

    @Test func 全部消すと輪郭がなくなる() {
        let result = edit(
            [contour(square(0.3, 0.3, 0.2))],
            combining: [square(0.1, 0.1, 0.8)],
            mode: .subtract
        )

        #expect(result.isEmpty)
    }

    // MARK: - 輪郭がまだないとき

    @Test func 輪郭がなければなぞりがそのまま輪郭になる() {
        let result = edit([], combining: [square(0.2, 0.2, 0.5)], mode: .add)

        #expect(result.count == 1)
        #expect(abs(totalArea(result) - 0.25) < 0.001)
    }

    @Test func 輪郭がなければ引いても何も起きない() {
        #expect(edit([], combining: [square(0.2, 0.2, 0.5)], mode: .subtract).isEmpty)
    }

    @Test func 面にならないなぞりは無視する() {
        let original = [contour(square(0.3, 0.3, 0.4))]

        #expect(edit(original, combining: [], mode: .add) == original)
        #expect(edit(original, combining: [[CGPoint(x: 0.1, y: 0.1)]], mode: .subtract) == original)
    }

    /// 消しゴムは極小の欠片を残します。見えないものが履歴と描画を重くするだけなので捨てます。
    @Test func 極小の欠片は捨てる() {
        let speck = square(0.5, 0.5, 0.001)

        #expect(edit([], combining: [speck], mode: .add).isEmpty)
        // 見える大きさなら残ります。
        #expect(!edit([], combining: [square(0.5, 0.5, 0.01)], mode: .add).isEmpty)
    }

    // MARK: - ブラシの形

    @Test func 点が2つのなぞりはカプセル1つになる() {
        let polygons = brush.polygons(
            for: [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.8, y: 0.5)],
            radius: 0.05
        )

        #expect(polygons.count == 1)
        let bounds = geometry.bounds(for: polygons[0])
        #expect(abs(bounds.minX - 0.15) < 0.001)
        #expect(abs(bounds.maxX - 0.85) < 0.001)
        #expect(abs(bounds.height - 0.1) < 0.001)
    }

    @Test func 点を1つ打つと円になる() {
        let polygons = brush.polygons(for: [CGPoint(x: 0.5, y: 0.5)], radius: 0.1)

        #expect(polygons.count == 1)
        let bounds = geometry.bounds(for: polygons[0])
        #expect(abs(bounds.midX - 0.5) < 0.001)
        #expect(abs(bounds.width - 0.2) < 0.01)
    }

    @Test func 同じ点が続いても潰れない() {
        let point = CGPoint(x: 0.5, y: 0.5)
        let polygons = brush.polygons(for: [point, point], radius: 0.05)

        #expect(polygons.count == 1)
        #expect(polygons[0].count >= 3)
    }

    @Test func 半径が0なら何も作らない() {
        #expect(brush.polygons(for: [CGPoint(x: 0.5, y: 0.5)], radius: 0).isEmpty)
    }

    // MARK: - 点の間引き

    @Test func 近すぎる点は間引かれる() {
        let simplifier = ContourSimplifier()
        let dense = (0..<100).map { index in
            CGPoint(x: 0.2 + Double(index) * 0.0001, y: 0.5)
        }

        #expect(simplifier.simplified(dense).count < dense.count)
    }

    /// 面でなくなるところまでは減らしません。
    @Test func 点が3つ未満には減らさない() {
        let simplifier = ContourSimplifier()
        let tiny = [
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.5001, y: 0.5),
            CGPoint(x: 0.5, y: 0.5001),
            CGPoint(x: 0.5001, y: 0.5001)
        ]

        #expect(simplifier.simplified(tiny).count >= 3)
    }
}
