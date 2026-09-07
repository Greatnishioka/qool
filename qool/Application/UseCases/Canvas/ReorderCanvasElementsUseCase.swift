import Foundation

/// 選んだ要素を重なり順の前後へ動かす。
///
/// **選択の中の並びは保ちます。** まとめて 1 つの塊として動かすので、
/// 複数選んで「最前面へ」しても、選択どうしの前後関係は変わりません。
nonisolated struct ReorderCanvasElementsUseCase {
    init() {}

    func callAsFunction(
        in elements: inout [CanvasElement],
        selectedIDs: Set<CanvasElement.ID>,
        to order: CanvasElementOrder
    ) {
        guard !selectedIDs.isEmpty, elements.contains(where: { selectedIDs.contains($0.id) }) else {
            return
        }

        switch order {
        case .front:
            elements = elements.filter { !selectedIDs.contains($0.id) }
                + elements.filter { selectedIDs.contains($0.id) }
        case .back:
            elements = elements.filter { selectedIDs.contains($0.id) }
                + elements.filter { !selectedIDs.contains($0.id) }
        case .forward:
            // **手前から処理します。** 奥から動かすと、まだ動いていない仲間を追い越します。
            for index in elements.indices.reversed() where selectedIDs.contains(elements[index].id) {
                let next = index + 1
                guard next < elements.count, !selectedIDs.contains(elements[next].id) else {
                    continue
                }

                elements.swapAt(index, next)
            }
        case .backward:
            for index in elements.indices where selectedIDs.contains(elements[index].id) {
                let previous = index - 1
                guard previous >= 0, !selectedIDs.contains(elements[previous].id) else {
                    continue
                }

                elements.swapAt(index, previous)
            }
        }
    }

    /// 動かせるか。**動かしても並びが変わらないなら `false`** を返します。
    /// 端に着いているボタンを押せてしまうと、押しても何も起きない操作になります。
    func canReorder(
        _ elements: [CanvasElement],
        selectedIDs: Set<CanvasElement.ID>,
        to order: CanvasElementOrder
    ) -> Bool {
        var reordered = elements
        callAsFunction(in: &reordered, selectedIDs: selectedIDs, to: order)

        return reordered.map(\.id) != elements.map(\.id)
    }
}
