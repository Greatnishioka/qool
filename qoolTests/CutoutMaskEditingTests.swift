import CoreGraphics
import Foundation
import Testing
@testable import qool

/// マスクの手直し（塗り・合成・履歴）の検証。
struct CutoutMaskEditingTests {
    private let stamp = CutoutMaskStamp()
    private let edit = EditCutoutMaskUseCase()
    private let filters = CutoutMaskFilters()

    private func emptyMask(_ size: Int = 40) -> CutoutMask? {
        CutoutMask(width: size, height: size, coverage: [UInt8](repeating: 0, count: size * size))
    }

    private func filledMask(_ size: Int = 40) -> CutoutMask? {
        CutoutMask(width: size, height: size, coverage: [UInt8](repeating: 255, count: size * size))
    }

    private func value(_ mask: CutoutMask, _ x: Double, _ y: Double) -> UInt8 {
        mask.value(at: CGPoint(x: x, y: y))
    }

    private func filledCount(_ mask: CutoutMask) -> Int {
        var count = 0

        for coverage in mask.coverage where coverage > 0 {
            count += 1
        }

        return count
    }

    // MARK: - なぞりを塗る

    @Test func なぞった線が塗られる() throws {
        let drawn = try #require(
            stamp.stamp(
                points: [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.8, y: 0.5)],
                radius: 0.05,
                softness: 0,
                width: 40,
                height: 40
            )
        )

        #expect(value(drawn, 0.5, 0.5) == 255)
        #expect(value(drawn, 0.5, 0.1) == 0)
    }

    /// **柔らかさがマスクにしかできないことの中身です。**
    @Test func 柔らかさを上げると縁に中間の値が出る() throws {
        let hard = try #require(
            stamp.stamp(
                points: [CGPoint(x: 0.5, y: 0.5)],
                radius: 0.2,
                softness: 0,
                width: 60,
                height: 60
            )
        )
        let soft = try #require(
            stamp.stamp(
                points: [CGPoint(x: 0.5, y: 0.5)],
                radius: 0.2,
                softness: 0.8,
                width: 60,
                height: 60
            )
        )

        var hardPartial = 0
        for coverage in hard.coverage where coverage > 0 && coverage < 255 {
            hardPartial += 1
        }

        var softPartial = 0
        for coverage in soft.coverage where coverage > 0 && coverage < 255 {
            softPartial += 1
        }

        #expect(softPartial > hardPartial)
    }

    /// 投げ縄は囲んだ内側を塗ります。
    @Test func 閉じたなぞりは内側が塗られる() throws {
        let drawn = try #require(
            stamp.stamp(
                points: [
                    CGPoint(x: 0.2, y: 0.2),
                    CGPoint(x: 0.8, y: 0.2),
                    CGPoint(x: 0.8, y: 0.8),
                    CGPoint(x: 0.2, y: 0.8)
                ],
                radius: 0.01,
                softness: 0,
                width: 40,
                height: 40,
                isClosed: true
            )
        )

        #expect(value(drawn, 0.5, 0.5) == 255)
        #expect(value(drawn, 0.05, 0.05) == 0)
    }

    @Test func 点がなければ塗らない() {
        #expect(stamp.stamp(points: [], radius: 0.1, softness: 0, width: 20, height: 20) == nil)
    }

    // MARK: - 合成

    @Test func 足すと塗った範囲が増える() throws {
        let base = try #require(emptyMask())
        let drawn = try #require(
            stamp.stamp(
                points: [CGPoint(x: 0.5, y: 0.5)],
                radius: 0.2,
                softness: 0,
                width: 40,
                height: 40
            )
        )

        let combined = edit(base, combining: drawn, mode: .add)

        #expect(value(combined, 0.5, 0.5) == 255)
    }

    @Test func 引くと塗った範囲が消える() throws {
        let base = try #require(filledMask())
        let drawn = try #require(
            stamp.stamp(
                points: [CGPoint(x: 0.5, y: 0.5)],
                radius: 0.2,
                softness: 0,
                width: 40,
                height: 40
            )
        )

        let combined = edit(base, combining: drawn, mode: .subtract)

        #expect(value(combined, 0.5, 0.5) == 0)
        #expect(value(combined, 0.05, 0.05) == 255)
    }

    /// **引き算に掛け算を使う理由の確認。**
    /// 単純に引くと、半分だけ覆われていた画素が一気に 0 まで落ちて縁が硬くなります。
    @Test func 柔らかいブラシで引くと縁に中間の値が残る() throws {
        let base = try #require(filledMask(60))
        let drawn = try #require(
            stamp.stamp(
                points: [CGPoint(x: 0.5, y: 0.5)],
                radius: 0.2,
                softness: 0.8,
                width: 60,
                height: 60
            )
        )

        let combined = edit(base, combining: drawn, mode: .subtract)
        var partial = 0

        for coverage in combined.coverage where coverage > 0 && coverage < 255 {
            partial += 1
        }

        #expect(partial > 0)
    }

    @Test func 格子が違えば合成しない() throws {
        let base = try #require(emptyMask(40))
        let other = try #require(filledMask(20))

        #expect(edit(base, combining: other, mode: .add) == base)
    }

    // MARK: - 履歴

    private func stroke(at x: Double, size: Int = 40) -> CutoutMask? {
        stamp.stamp(
            points: [CGPoint(x: x, y: 0.5)],
            radius: 0.1,
            softness: 0,
            width: size,
            height: size
        )
    }

    @Test func 積んで戻して進める() throws {
        let base = try #require(emptyMask())
        var history = CutoutMaskEditHistory(base, limit: 10)

        let first = edit(base, combining: try #require(stroke(at: 0.3)), mode: .add)
        history.record(first)
        let second = edit(first, combining: try #require(stroke(at: 0.7)), mode: .add)
        history.record(second)

        #expect(history.canUndo)
        #expect(!history.canRedo)

        history.undo()
        #expect(history.current == first)
        #expect(history.canRedo)

        history.redo()
        #expect(history.current == second)
    }

    @Test func 戻したあとに積むとやり直せなくなる() throws {
        let base = try #require(emptyMask())
        var history = CutoutMaskEditHistory(base, limit: 10)

        history.record(edit(base, combining: try #require(stroke(at: 0.3)), mode: .add))
        history.undo()
        history.record(edit(base, combining: try #require(stroke(at: 0.7)), mode: .add))

        #expect(!history.canRedo)
    }

    /// **何も変わらない手は積みません。** 押し戻せる手数を無駄に消費しないためです。
    @Test func 変化のない手は積まれない() throws {
        let base = try #require(emptyMask())
        var history = CutoutMaskEditHistory(base, limit: 10)

        history.record(base)

        #expect(!history.canUndo)
    }

    @Test func 上限を超えると古い手から捨てる() throws {
        let base = try #require(emptyMask())
        var history = CutoutMaskEditHistory(base, limit: 2)
        var mask = base

        for index in 0..<4 {
            mask = edit(
                mask,
                combining: try #require(stroke(at: 0.2 + Double(index) * 0.15)),
                mode: .add
            )
            history.record(mask)
        }

        history.undo()
        history.undo()

        // 2 手ぶんしか戻せません。
        #expect(!history.canUndo)
    }

    @Test func 格子が違う手は積まれない() throws {
        let base = try #require(emptyMask(40))
        var history = CutoutMaskEditHistory(base, limit: 10)

        history.record(try #require(filledMask(20)))

        #expect(!history.canUndo)
    }

    // MARK: - 単位空間への置き直し

    /// 切り詰めたマスクを、編集で使う格子へ載せ直します。
    @Test func 切り詰めたマスクを全体の格子へ戻せる() throws {
        let trimmed = try #require(
            CutoutMask(
                extent: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                width: 2,
                height: 2,
                coverage: [255, 255, 255, 255]
            )
        )

        let placed = try #require(filters.placedInUnitSpace(trimmed, width: 40, height: 40))

        #expect(placed.extent == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(value(placed, 0.5, 0.5) == 255)
        #expect(value(placed, 0.05, 0.05) == 0)
        #expect(filledCount(placed) > 0)
    }
}
