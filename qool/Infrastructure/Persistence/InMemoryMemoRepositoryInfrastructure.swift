import CoreGraphics
import Foundation
import Synchronization

/// テストとプレビュー用。可変状態は `Mutex` で守ります。
nonisolated final class InMemoryMemoRepositoryInfrastructure: MemoRepositoryProtocol {
    private let memos: Mutex<[Memo]>

    init(seedMemos: [Memo] = InMemoryMemoRepositoryInfrastructure.defaultSeedMemos) {
        memos = Mutex(seedMemos)
    }

    func loadMemos() throws -> [Memo] {
        memos.withLock { $0.sorted { $0.updatedAt > $1.updatedAt } }
    }

    func save(_ memo: Memo) async throws {
        memos.withLock { memos in
            if let index = memos.firstIndex(where: { $0.id == memo.id }) {
                memos[index] = memo
            } else {
                memos.append(memo)
            }
        }
    }

    func delete(id: Memo.ID) async throws {
        memos.withLock { $0.removeAll { $0.id == id } }
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
                    kind: .text,
                    frame: CGRect(x: 84, y: 112, width: 156, height: 76),
                    fillColor: .clear,
                    showsStroke: false,
                    text: "牛乳\n卵\nコーヒー"
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
