import Foundation
import Testing
@testable import qool

/// 切り抜きの手直しの履歴（[ContourEditHistory](../qool/Domain/Models/ContourEditHistory.swift)）の検証。
struct ContourEditHistoryTests {
    private func contour(_ side: Double, points count: Int = 4) -> [CanvasPathContour] {
        [CanvasPathContour(points: (0..<count).map { index in
            let angle = Double(index) / Double(count) * .pi * 2

            return NormalizedPoint(x: 0.5 + cos(angle) * side, y: 0.5 + sin(angle) * side)
        })]
    }

    @Test func 積んで戻してやり直せる() {
        var history = ContourEditHistory(contour(0.1))
        let second = contour(0.2)
        let third = contour(0.3)

        history.record(second)
        history.record(third)
        #expect(history.current == third)

        history.undo()
        #expect(history.current == second)

        history.undo()
        #expect(history.current == contour(0.1))
        #expect(!history.canUndo)

        history.redo()
        #expect(history.current == second)
    }

    /// 同じ結果で埋まると、戻せる手数が実質減ります。
    @Test func 変化がなければ積まない() {
        var history = ContourEditHistory(contour(0.1))

        history.record(contour(0.1))

        #expect(!history.canUndo)
    }

    /// 戻した先から別の編集をしたら、やり直せる先は消えます。
    @Test func 戻したあとに編集すると先の枝は消える() {
        var history = ContourEditHistory(contour(0.1))
        history.record(contour(0.2))
        history.undo()
        #expect(history.canRedo)

        history.record(contour(0.3))

        #expect(!history.canRedo)
        #expect(history.current == contour(0.3))
    }

    @Test func 上限を超えたら古いほうから捨てる() {
        var history = ContourEditHistory(contour(0.01), limit: 3)

        for step in 1...10 {
            history.record(contour(Double(step) * 0.02))
        }

        #expect(history.undoCount == 3)
    }

    @Test func 上限は範囲へ丸める() {
        #expect(ContourEditHistory(contour(0.1), limit: 0).limit == ContourEditHistory.limitRange.lowerBound)
        #expect(ContourEditHistory(contour(0.1), limit: 9999).limit == ContourEditHistory.limitRange.upperBound)
    }

    /// 下げた直後だけ以前の上限のまま戻せる、という食い違いを避けます。
    @Test func 上限を下げるとその場ではみ出す分を捨てる() {
        var history = ContourEditHistory(contour(0.01), limit: 20)
        for step in 1...15 {
            history.record(contour(Double(step) * 0.02))
        }
        #expect(history.undoCount == 15)

        history.updateLimit(5)

        #expect(history.undoCount == 5)
        // 直前の状態は残っています。
        #expect(history.canUndo)
    }

    /// 形の複雑さは手数から読めないので、合計の大きさでも打ち切ります。
    ///
    /// **実測では 500 手でも 1 件 45KB 程度**で、この上限には届きません。安全網としての確認です。
    @Test func 合計が上限を超えたら手数が残っていても捨てる() {
        // 1 件 128KB。250 件で 32MB を超えます。
        let pointCount = 8000
        var history = ContourEditHistory(
            contour(0.01, points: pointCount),
            limit: ContourEditHistory.limitRange.upperBound
        )

        for step in 1...300 {
            history.record(contour(Double(step) * 0.001, points: pointCount))
        }

        #expect(history.estimatedBytes <= ContourEditHistory.maximumTotalBytes)
        #expect(history.undoCount < 300)
        // 少なくとも直前へは戻せます。
        #expect(history.canUndo)
    }

    @Test func 戻す先がなければ何も起きない() {
        var history = ContourEditHistory(contour(0.1))
        let original = history.current

        history.undo()
        history.redo()

        #expect(history.current == original)
    }

    // MARK: - 設定

    @MainActor
    @Test func 上限は保存して読み戻せる() throws {
        let defaults = try #require(UserDefaults(suiteName: "qool.history.\(UUID().uuidString)"))
        let settings = UserDefaultsAppSettingsInfrastructure(defaults: defaults)

        #expect(settings.editHistoryLimit == ContourEditHistory.defaultLimit)

        settings.editHistoryLimit = 320

        #expect(UserDefaultsAppSettingsInfrastructure(defaults: defaults).editHistoryLimit == 320)
    }

    @MainActor
    @Test func 範囲外の上限は丸めて読む() throws {
        let defaults = try #require(UserDefaults(suiteName: "qool.history.\(UUID().uuidString)"))
        defaults.set(9999, forKey: "editHistoryLimit")

        #expect(
            UserDefaultsAppSettingsInfrastructure(defaults: defaults).editHistoryLimit
                == ContourEditHistory.limitRange.upperBound
        )
    }
}
