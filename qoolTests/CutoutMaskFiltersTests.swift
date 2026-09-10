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

    /// **半径 2 以下は正方形のままです。** 角を落とすには縦横の窓に 1 画素以上
    /// 残す必要があり、それができるのは半径 3 からです。
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

    // MARK: - 画素数の変更（片方向）

    /// **往復では裏返りを見つけられません。** 縮めてから広げれば元へ戻るので、
    /// 符号化と復号が互いの間違いを打ち消すのと同じことが起きます。
    /// 上下左右で違う形を入れて、片方向で確かめます。
    @Test func 画素数を変えても上下左右が入れ替わらない() throws {
        // 左上の 2×2 だけが埋まった 4×4。
        var coverage = [UInt8](repeating: 0, count: 16)
        for row in 0..<2 {
            for column in 0..<2 {
                coverage[row * 4 + column] = 255
            }
        }
        let mask = try #require(CutoutMask(width: 4, height: 4, coverage: coverage))

        let resized = try #require(filters.resized(mask, width: 8, height: 8))

        let topLeft = resized.coverage[0]
        let topRight = resized.coverage[7]
        let bottomLeft = resized.coverage[56]
        let bottomRight = resized.coverage[63]

        // 補間が掛かるので、端の値そのものではなく濃さで見ます。
        #expect(topLeft > 200)
        #expect(topRight < 55)
        #expect(bottomLeft < 55)
        #expect(bottomRight < 55)
    }

    // MARK: - 八角形への丸め

    /// **角が落ちることの確認。** 縦横に窓を滑らせるだけだと、斜めへ半径の
    /// √2 倍まで出て角が張ります（[issue #10](https://github.com/Greatnishioka/qool/issues/10)）。
    @Test func 半径3以上では角が落ちる() throws {
        let mask = try #require(centerDot())
        let dilated = try #require(filters.dilated(mask, radiusX: 6, radiusY: 6))

        let right = value(dilated, dx: 6, dy: 0)
        let bottom = value(dilated, dx: 0, dy: 6)
        let slope = value(dilated, dx: 5, dy: 3)
        let corner = value(dilated, dx: 5, dy: 5)
        let farCorner = value(dilated, dx: 6, dy: 6)

        // 縦横へは半径ぶん出ます。
        #expect(right == 255)
        #expect(bottom == 255)
        // 斜めは削られます。
        #expect(slope == 255)
        #expect(corner == 0)
        #expect(farCorner == 0)
    }

    /// **穴が開いていないことの確認。** 斜めの窓は 1 つ飛ばしの格子しか覆いません。
    /// 縦横の窓が隙間を埋めそこねると、格子状に抜けます。
    @Test func 八角形に隙間ができない() throws {
        let mask = try #require(centerDot())
        let dilated = try #require(filters.dilated(mask, radiusX: 6, radiusY: 6))
        let filled = filledCount(dilated)

        // `|x| <= 6`、`|y| <= 6`、`|x| + |y| <= 8` の八角形。
        // 正方形なら 13 × 13 = 169 で、四隅から 1 + 2 + 3 + 4 = 10 ずつ落ちます。
        #expect(filled == 129)
    }

    /// **非等比でも角は丸いままです。** 短いほうの半径で角を落とし、
    /// 残りを長いほうへ伸ばすので、形は角丸の長方形になります。
    @Test func 非等比でも角が落ちる() throws {
        let mask = try #require(centerDot())
        let dilated = try #require(filters.dilated(mask, radiusX: 8, radiusY: 6))

        let right = value(dilated, dx: 8, dy: 0)
        let bottom = value(dilated, dx: 0, dy: 6)
        let edge = value(dilated, dx: 8, dy: 2)
        let corner = value(dilated, dx: 8, dy: 3)

        #expect(right == 255)
        #expect(bottom == 255)
        #expect(edge == 255)
        #expect(corner == 0)
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
