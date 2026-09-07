import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 重なり順の入れ替えの検証。
///
/// **`Canvas.elements` の並びがそのまま重なり順です。** 後ろほど手前に描かれます。
struct CanvasElementOrderTests {
    private let reorder = ReorderCanvasElementsUseCase()

    private func elements(_ count: Int) -> [CanvasElement] {
        (0..<count).map { _ in
            CanvasElement(kind: .rectangle, frame: .zero, fillColor: .paper)
        }
    }

    private func ids(_ elements: [CanvasElement], _ indices: [Int]) -> Set<CanvasElement.ID> {
        Set(indices.map { elements[$0].id })
    }

    private func order(of elements: [CanvasElement], in original: [CanvasElement]) -> [Int] {
        elements.map { element in
            original.firstIndex { $0.id == element.id } ?? -1
        }
    }

    @Test func 最前面へ動かすと末尾に来る() {
        let original = elements(4)
        var moved = original

        reorder(in: &moved, selectedIDs: ids(original, [1]), to: .front)

        #expect(order(of: moved, in: original) == [0, 2, 3, 1])
    }

    @Test func 最背面へ動かすと先頭に来る() {
        let original = elements(4)
        var moved = original

        reorder(in: &moved, selectedIDs: ids(original, [2]), to: .back)

        #expect(order(of: moved, in: original) == [2, 0, 1, 3])
    }

    @Test func 前面へは1つだけ進む() {
        let original = elements(4)
        var moved = original

        reorder(in: &moved, selectedIDs: ids(original, [1]), to: .forward)

        #expect(order(of: moved, in: original) == [0, 2, 1, 3])
    }

    @Test func 背面へは1つだけ下がる() {
        let original = elements(4)
        var moved = original

        reorder(in: &moved, selectedIDs: ids(original, [2]), to: .backward)

        #expect(order(of: moved, in: original) == [0, 2, 1, 3])
    }

    /// **選択の中の並びは保ちます。** まとめて 1 つの塊として動かします。
    @Test func 複数選択でも選択どうしの前後は変わらない() {
        let original = elements(5)
        var moved = original

        reorder(in: &moved, selectedIDs: ids(original, [0, 2]), to: .front)

        #expect(order(of: moved, in: original) == [1, 3, 4, 0, 2])
    }

    /// 隣り合った選択が互いを追い越さないことの確認。
    @Test func 隣り合った複数選択は塊のまま1つ進む() {
        let original = elements(4)
        var moved = original

        reorder(in: &moved, selectedIDs: ids(original, [0, 1]), to: .forward)

        #expect(order(of: moved, in: original) == [2, 0, 1, 3])
    }

    @Test func 端に着いていれば動かない() {
        let original = elements(3)
        var moved = original

        reorder(in: &moved, selectedIDs: ids(original, [2]), to: .forward)

        #expect(order(of: moved, in: original) == [0, 1, 2])
    }

    @Test func 選択がなければ何も動かない() {
        let original = elements(3)
        var moved = original

        reorder(in: &moved, selectedIDs: [], to: .front)

        #expect(order(of: moved, in: original) == [0, 1, 2])
    }

    // MARK: - 動かせるかどうか

    @Test func 端に着いていれば動かせないと答える() {
        let original = elements(3)

        #expect(reorder.canReorder(original, selectedIDs: ids(original, [2]), to: .front) == false)
        #expect(reorder.canReorder(original, selectedIDs: ids(original, [2]), to: .forward) == false)
        #expect(reorder.canReorder(original, selectedIDs: ids(original, [2]), to: .backward))
        #expect(reorder.canReorder(original, selectedIDs: ids(original, [2]), to: .back))
    }

    @Test func 全部選んでいればどちらへも動かせない() {
        let original = elements(3)
        let all = ids(original, [0, 1, 2])

        #expect(CanvasElementOrder.allCases.allSatisfy { order in
            reorder.canReorder(original, selectedIDs: all, to: order) == false
        })
    }
}
