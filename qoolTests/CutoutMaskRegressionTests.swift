import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 一度落とした不具合を守るためのテスト。
///
/// **いずれも静かに壊れる種類でした。** ビルドは通り、画面も一見動きます。
struct CutoutMaskRegressionTests {
    private let cropGeometry = CutoutCropGeometry()
    private let baseSelector = CutoutEditingBase()

    private func mask(_ extent: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> CutoutMask? {
        CutoutMask(extent: extent, width: 2, height: 2, coverage: [255, 255, 255, 255])
    }

    private func contour(_ rect: CGRect) -> CanvasPathContour {
        CanvasPathContour(points: [
            NormalizedPoint(x: rect.minX, y: rect.minY),
            NormalizedPoint(x: rect.maxX, y: rect.minY),
            NormalizedPoint(x: rect.maxX, y: rect.maxY),
            NormalizedPoint(x: rect.minX, y: rect.maxY)
        ])
    }

    // MARK: - 手直しの土台

    /// **なぞり直したら既存のマスクは使いません。**
    /// 使ってしまうと、矩形補正や手描きを選んでも古い形のまま適用されます。
    @Test func なぞり直すと既存のマスクは土台にしない() throws {
        let existing = try #require(mask())

        let selected = baseSelector.mask(existing: existing, candidate: nil, hasRetraced: true)

        // 候補がマスクを持たないので `nil`。呼び出し側が候補の輪郭から起こします。
        #expect(selected == nil)
    }

    @Test func なぞり直して候補がマスクを持てばそれを使う() throws {
        let existing = try #require(mask())
        let candidate = try #require(mask(CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)))

        let selected = baseSelector.mask(existing: existing, candidate: candidate, hasRetraced: true)

        #expect(selected?.extent == candidate.extent)
    }

    /// なぞり直していなければ、既存のマスクがそのまま土台です。
    @Test func なぞり直していなければ既存のマスクを使う() throws {
        let existing = try #require(mask())

        let selected = baseSelector.mask(existing: existing, candidate: nil, hasRetraced: false)

        #expect(selected?.extent == existing.extent)
    }

    // MARK: - 切り詰めと薄い被覆

    /// **薄く覆っている部分まで含めて切り詰めます。**
    /// 輪郭はしきい値を超えた濃さしか表さないので、含めないと
    /// 髪やガラスの薄い部分の画像が捨てられます。
    @Test func 輪郭の外にある薄い被覆も切り詰めに含める() throws {
        let contours = [contour(CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1))]
        let pixelSize = CGSize(width: 2000, height: 2000)
        let displaySize = CGSize(width: 320, height: 320)

        let narrow = try #require(
            cropGeometry.crop(for: contours, imagePixelSize: pixelSize, displaySize: displaySize)
        )
        // 輪郭からは離れているが、薄く覆っている範囲。
        let wide = try #require(
            cropGeometry.crop(
                for: contours,
                imagePixelSize: pixelSize,
                displaySize: displaySize,
                covering: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
            )
        )

        #expect(wide.normalizedRect.width > narrow.normalizedRect.width)
        #expect(wide.normalizedRect.minX < narrow.normalizedRect.minX)
        #expect(wide.normalizedRect.maxX > narrow.normalizedRect.maxX)
    }

    @Test func 含める範囲を渡さなければ輪郭だけで決まる() throws {
        let contours = [contour(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))]
        let pixelSize = CGSize(width: 2000, height: 2000)
        let displaySize = CGSize(width: 320, height: 320)

        let plain = try #require(
            cropGeometry.crop(for: contours, imagePixelSize: pixelSize, displaySize: displaySize)
        )
        let same = try #require(
            cropGeometry.crop(
                for: contours,
                imagePixelSize: pixelSize,
                displaySize: displaySize,
                covering: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
            )
        )

        // 輪郭の内側に収まる範囲を渡しても広がりません。
        #expect(abs(plain.normalizedRect.width - same.normalizedRect.width) < 0.0001)
    }

    // MARK: - 履歴の上限と格子

    /// **覆う範囲が違えば積みません。** 画素だけ戻って範囲が戻らないと、
    /// 元のマスクへ復元できません。
    @Test func 覆う範囲が違う手は積まれない() throws {
        let base = try #require(mask())
        var history = CutoutMaskEditHistory(base, limit: 10)

        let moved = try #require(
            CutoutMask(
                extent: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
                width: 2,
                height: 2,
                coverage: [0, 0, 0, 0]
            )
        )
        history.record(moved)

        #expect(!history.canUndo)
    }

    /// **手数だけでは足りません。** 全面を塗り替える手を積み続けると、
    /// 上限の手数に達する前に総量が膨らみます。
    @Test func 総量の上限を超えると古い手から捨てる() throws {
        let size = 256
        let empty = try #require(
            CutoutMask(width: size, height: size, coverage: [UInt8](repeating: 0, count: size * size))
        )
        var history = CutoutMaskEditHistory(empty, limit: 500)

        // 1 手あたり before + after で 128KB。32MB を超えるまで積みます。
        var value: UInt8 = 1
        for _ in 0..<300 {
            let filled = try #require(
                CutoutMask(
                    width: size,
                    height: size,
                    coverage: [UInt8](repeating: value, count: size * size)
                )
            )
            history.record(filled)
            value = value &+ 1
        }

        var steps = 0
        while history.canUndo {
            history.undo()
            steps += 1
        }

        // 手数の上限（500）ではなく、総量の上限で頭打ちになります。
        #expect(steps < 300)
        #expect(steps > 0)
    }
}
