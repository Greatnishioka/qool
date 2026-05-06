import CoreGraphics
import Foundation

final class InMemoryMemoRepository: MemoRepository {
    private var memos: [Memo]

    init(seedMemos: [Memo] = InMemoryMemoRepository.defaultSeedMemos) {
        self.memos = seedMemos
    }

    func loadMemos() -> [Memo] {
        memos.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ memo: Memo) {
        if let index = memos.firstIndex(where: { $0.id == memo.id }) {
            memos[index] = memo
        } else {
            memos.append(memo)
        }
    }

    func delete(id: Memo.ID) {
        memos.removeAll { $0.id == id }
    }

    private static let defaultSeedMemos: [Memo] = [
        Memo(
            title: "買い物メモ",
            canvas: Canvas(elements: [
                CanvasElement(
                    kind: .rectangle,
                    frame: CGRect(x: 52, y: 80, width: 220, height: 140),
                    fillColor: .paper
                ),
                CanvasElement(
                    kind: .textPath,
                    frame: CGRect(x: 84, y: 112, width: 156, height: 76),
                    fillColor: .mint
                )
            ])
        ),
        Memo(
            title: "切り抜きサンプル",
            canvas: Canvas(elements: [
                CanvasElement(
                    kind: .imageCutout,
                    frame: CGRect(x: 72, y: 92, width: 200, height: 170),
                    fillColor: .coral
                )
            ])
        )
    ]
}
