import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 切り抜きマスクと、輪郭からの起こしの検証。
struct CutoutMaskTests {
    private let rasterizer = CutoutMaskRasterizer()

    private func contour(_ rect: CGRect) -> CanvasPathContour {
        CanvasPathContour(points: [
            NormalizedPoint(x: rect.minX, y: rect.minY),
            NormalizedPoint(x: rect.maxX, y: rect.minY),
            NormalizedPoint(x: rect.maxX, y: rect.maxY),
            NormalizedPoint(x: rect.minX, y: rect.maxY)
        ])
    }

    // MARK: - 起こし

    @Test func 輪郭の内側が塗られる() throws {
        let mask = try #require(
            rasterizer.mask(
                from: [contour(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))],
                width: 100,
                height: 100
            )
        )

        #expect(mask.value(at: CGPoint(x: 0.5, y: 0.5)) == 255)
        #expect(mask.value(at: CGPoint(x: 0.05, y: 0.05)) == 0)
    }

    /// **上下が裏返らないことの確認。** 輪郭は左上原点、`CGContext` は左下原点なので、
    /// 揃え損ねるとマスクだけ上下が逆になります。移植時に踏んだ落とし穴と同じ形です。
    @Test func 上半分を塗ると上半分が覆われる() throws {
        let mask = try #require(
            rasterizer.mask(
                from: [contour(CGRect(x: 0, y: 0, width: 1, height: 0.5))],
                width: 40,
                height: 40
            )
        )

        #expect(mask.value(at: CGPoint(x: 0.5, y: 0.1)) == 255)
        #expect(mask.value(at: CGPoint(x: 0.5, y: 0.9)) == 0)
        // 配列の先頭は左上。ここも覆われている必要があります。
        #expect(mask.coverage[0] == 255)
    }

    /// **縁に中間値が出ることの確認。** これが多角形との決定的な違いです。
    @Test func 斜めの縁には中間の被覆率が出る() throws {
        let triangle = CanvasPathContour(points: [
            NormalizedPoint(x: 0.1, y: 0.1),
            NormalizedPoint(x: 0.9, y: 0.9),
            NormalizedPoint(x: 0.1, y: 0.9)
        ])

        let mask = try #require(rasterizer.mask(from: [triangle], width: 80, height: 80))

        #expect(mask.coverage.contains { $0 > 0 && $0 < 255 })
    }

    /// 穴は偶奇規則で抜けます。取っ手の内側のような形をそのまま扱えます。
    @Test func 内側の輪郭は穴として抜ける() throws {
        let mask = try #require(
            rasterizer.mask(
                from: [
                    contour(CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)),
                    contour(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
                ],
                width: 100,
                height: 100
            )
        )

        #expect(mask.value(at: CGPoint(x: 0.2, y: 0.2)) == 255)
        #expect(mask.value(at: CGPoint(x: 0.5, y: 0.5)) == 0)
    }

    @Test func 点が足りない輪郭からは起こさない() {
        let line = CanvasPathContour(points: [
            NormalizedPoint(x: 0.1, y: 0.1),
            NormalizedPoint(x: 0.9, y: 0.9)
        ])

        #expect(rasterizer.mask(from: [line], width: 50, height: 50) == nil)
        #expect(rasterizer.mask(from: [], width: 50, height: 50) == nil)
    }

    // MARK: - 参照

    @Test func 画素数と配列の長さが合わなければ作れない() {
        #expect(CutoutMask(width: 4, height: 4, coverage: [UInt8](repeating: 0, count: 15)) == nil)
        #expect(CutoutMask(width: 0, height: 4, coverage: []) == nil)
    }

    @Test func 覆う範囲の外は0を返す() throws {
        let mask = try #require(
            CutoutMask(
                extent: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                width: 2,
                height: 2,
                coverage: [255, 255, 255, 255]
            )
        )

        #expect(mask.value(at: CGPoint(x: 0.5, y: 0.5)) == 255)
        #expect(mask.value(at: CGPoint(x: 0.1, y: 0.5)) == 0)
        #expect(mask.value(at: CGPoint(x: 0.5, y: 0.9)) == 0)
    }

    /// **境界の扱いの確認。** 各セルの左上を含み、右下を含まない半開区間です。
    @Test func 画素の境界は左上を含んで右下を含まない() throws {
        let mask = try #require(CutoutMask(width: 2, height: 2, coverage: [10, 20, 30, 40]))

        #expect(mask.value(at: CGPoint(x: 0, y: 0)) == 10)
        #expect(mask.value(at: CGPoint(x: 0.49, y: 0.49)) == 10)
        #expect(mask.value(at: CGPoint(x: 0.5, y: 0)) == 20)
        #expect(mask.value(at: CGPoint(x: 0, y: 0.5)) == 30)
        #expect(mask.value(at: CGPoint(x: 0.99, y: 0.99)) == 40)
        // 右端と下端そのものは範囲の外です。
        #expect(mask.value(at: CGPoint(x: 1, y: 0.5)) == 0)
        #expect(mask.value(at: CGPoint(x: 0.5, y: 1)) == 0)
    }

    @Test func 成立しない範囲のマスクは作れない() {
        let coverage: [UInt8] = [1, 2, 3, 4]

        #expect(CutoutMask(extent: CGRect(x: 0, y: 0, width: 0, height: 1), width: 2, height: 2, coverage: coverage) == nil)
        #expect(CutoutMask(extent: CGRect(x: 0, y: 0, width: -1, height: 1), width: 2, height: 2, coverage: coverage) == nil)
        #expect(CutoutMask(extent: CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1), width: 2, height: 2, coverage: coverage) == nil)
    }

    /// 開いた輪郭は塗りません。なぞり途中の線が面になるのを防ぎます。
    @Test func 開いた輪郭からは起こさない() {
        let open = CanvasPathContour(
            points: [
                NormalizedPoint(x: 0.2, y: 0.2),
                NormalizedPoint(x: 0.8, y: 0.2),
                NormalizedPoint(x: 0.8, y: 0.8)
            ],
            isClosed: false
        )

        #expect(rasterizer.mask(from: [open], width: 40, height: 40) == nil)
    }

    // MARK: - 切り詰め

    /// **保存と描画の前に通します。** 隅だけを囲んだ場合でも全面ぶんの画素を抱えません。
    @Test func 被覆のある範囲まで切り詰める() throws {
        let mask = try #require(
            rasterizer.mask(
                from: [contour(CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.25))],
                width: 100,
                height: 100
            )
        )

        let trimmed = try #require(mask.trimmed())

        #expect(trimmed.width < mask.width)
        #expect(trimmed.height < mask.height)
        // 覆う範囲が動いても、同じ位置の被覆率は変わりません。
        #expect(trimmed.value(at: CGPoint(x: 0.6, y: 0.6)) == 255)
        #expect(trimmed.value(at: CGPoint(x: 0.2, y: 0.2)) == 0)
        #expect(abs(trimmed.extent.minX - 0.5) < 0.02)
    }

    @Test func 全部が空なら切り詰められない() throws {
        let mask = try #require(CutoutMask(width: 4, height: 4, coverage: [UInt8](repeating: 0, count: 16)))

        #expect(mask.trimmed() == nil)
    }

    /// **既に絞った範囲をさらに絞ったときの確認。** 座標が合成されます。
    @Test func 部分的な範囲をさらに切り詰めても位置が合う() throws {
        let coverage: [UInt8] = [
            0, 0, 0, 0,
            0, 255, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0
        ]
        let mask = try #require(
            CutoutMask(
                extent: CGRect(x: 0.2, y: 0.4, width: 0.4, height: 0.4),
                width: 4,
                height: 4,
                coverage: coverage
            )
        )

        let trimmed = try #require(mask.trimmed())

        #expect(trimmed.width == 1)
        #expect(trimmed.height == 1)
        // 元の範囲の 1/4 だけ右下へ進んだ位置に、1/4 の大きさで載ります。
        #expect(abs(trimmed.extent.minX - (0.2 + 0.4 * 0.25)) < 0.0001)
        #expect(abs(trimmed.extent.minY - (0.4 + 0.4 * 0.25)) < 0.0001)
        #expect(abs(trimmed.extent.width - 0.1) < 0.0001)
        // 切り詰めても、同じ位置を指せば同じ値が返ります。
        #expect(trimmed.value(at: CGPoint(x: 0.35, y: 0.55)) == 255)
    }

    @Test func 切り詰める余地がなければそのまま返す() throws {
        let mask = try #require(CutoutMask(width: 2, height: 2, coverage: [255, 255, 255, 255]))

        #expect(mask.trimmed() == mask)
    }
}
