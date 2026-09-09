import CoreGraphics
import Foundation
import Testing
@testable import qool

/// マスクの膨張の検証。
///
/// **余白の作り方が輪郭の押し出しから変わります。** どの向きにも同じだけ広がることを固定します。
///
/// **`#expect` の中では複雑な式を書きません。** 添字計算や絞り込みを直接入れると、
/// マクロの展開でビルドが落ちます（実測）。値は先に取り出します。
struct CutoutMaskFiltersTests {
    private let filters = CutoutMaskFilters()

    /// 中央 1 画素だけが埋まった 5×5。
    private func centerDot() -> CutoutMask? {
        var coverage = [UInt8](repeating: 0, count: 25)
        coverage[12] = 255

        return CutoutMask(width: 5, height: 5, coverage: coverage)
    }

    private func filledCount(_ mask: CutoutMask, value: UInt8 = 255) -> Int {
        var count = 0

        for coverage in mask.coverage where coverage == value {
            count += 1
        }

        return count
    }

    /// 中央から `dx`, `dy` 画素ずれた位置の被覆率。
    private func value(_ mask: CutoutMask, dx: Int, dy: Int) -> UInt8 {
        let column = mask.width / 2 + dx
        let row = mask.height / 2 + dy

        guard column >= 0, column < mask.width, row >= 0, row < mask.height else {
            return 0
        }

        return mask.coverage[row * mask.width + column]
    }

    @Test func 半径0なら何も変えない() throws {
        let mask = try #require(centerDot())
        let dilated = filters.dilated(mask, radiusX: 0, radiusY: 0)

        #expect(dilated == mask)
    }

    /// **点は正方形に広がります。** 距離ではなく窓の最大値を取るためです。
    @Test func 点が1画素ぶん縦横に広がる() throws {
        let mask = try #require(centerDot())
        let dilated = try #require(filters.dilated(mask, radiusX: 1, radiusY: 1))
        let filled = filledCount(dilated)

        // 画素は上下左右に 1 ずつ増えます。
        #expect(dilated.width == 7)
        #expect(dilated.height == 7)
        // 元の中央のまわり 3×3 が埋まります。
        #expect(filled == 9)
    }

    /// **どの向きにも同じだけ広がることの確認。**
    /// 重心からの押し出しでは、凹凸のある形で向きごとに量が変わっていました。
    @Test func 広がる量は向きによらない() throws {
        let mask = try #require(centerDot())
        let dilated = try #require(filters.dilated(mask, radiusX: 2, radiusY: 2))

        let left = value(dilated, dx: -2, dy: 0)
        let right = value(dilated, dx: 2, dy: 0)
        let top = value(dilated, dx: 0, dy: -2)
        let bottom = value(dilated, dx: 0, dy: 2)
        let outside = value(dilated, dx: -3, dy: 0)

        #expect(left == 255)
        #expect(right == 255)
        #expect(top == 255)
        #expect(bottom == 255)
        #expect(outside == 0)
    }

    @Test func 縦横で別の半径を指定できる() throws {
        let mask = try #require(centerDot())
        let dilated = try #require(filters.dilated(mask, radiusX: 3, radiusY: 1))
        let filled = filledCount(dilated)

        #expect(dilated.width == 11)
        #expect(dilated.height == 7)
        // 横 7 × 縦 3 が埋まります。
        #expect(filled == 21)
    }

    /// 中間の被覆率も、より濃いほうが広がります。
    @Test func 中間の値も最大値として広がる() throws {
        var coverage = [UInt8](repeating: 0, count: 9)
        coverage[4] = 128
        let mask = try #require(CutoutMask(width: 3, height: 3, coverage: coverage))
        let dilated = try #require(filters.dilated(mask, radiusX: 1, radiusY: 1))
        let filled = filledCount(dilated, value: 128)

        #expect(filled == 9)
    }

    /// **広げた分だけ覆う範囲も外へ出ます。** 揃えないと絵がずれます。
    @Test func 覆う範囲も広がった分だけ外へ出る() throws {
        let mask = try #require(
            CutoutMask(
                extent: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5),
                width: 5,
                height: 5,
                coverage: [UInt8](repeating: 0, count: 25)
            )
        )
        let dilated = try #require(filters.dilated(mask, radiusX: 1, radiusY: 1))
        let extent = dilated.extent

        // 1 画素は 0.5 / 5 = 0.1 ぶん。
        #expect(abs(extent.minX - 0.1) < 0.0001)
        #expect(abs(extent.width - 0.7) < 0.0001)
    }

    // MARK: - 表示ポイントからの換算

    /// **非等比に伸ばすと縦横で比が変わります。**
    /// 片方の比だけで換算すると、引き伸ばした向きの余白が細くなります。
    @Test func 非等比に伸ばすと縦横で半径が変わる() throws {
        let coverage = [UInt8](repeating: 0, count: 10000)
        let mask = try #require(CutoutMask(width: 100, height: 100, coverage: coverage))

        let radius = filters.radius(
            forPointPadding: 10,
            mask: mask,
            elementSize: CGSize(width: 200, height: 100)
        )

        // 横は 1 画素 = 2pt なので半径 5、縦は 1 画素 = 1pt なので半径 10。
        #expect(radius.x == 5)
        #expect(radius.y == 10)
    }

    @Test func 余白が0なら半径も0() throws {
        let mask = try #require(centerDot())

        let radius = filters.radius(
            forPointPadding: 0,
            mask: mask,
            elementSize: CGSize(width: 100, height: 100)
        )

        #expect(radius.x == 0)
        #expect(radius.y == 0)
    }
}
