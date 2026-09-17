import Foundation
import Synchronization

/// 付箋の書き込みを**付箋ごとに直列化**する。
///
/// 本文は 1 打鍵ごと、位置はドラッグのたびに保存されます。素のまま投げると
/// **完了の順番が入れ替わり、古い本文が最後に書かれて巻き戻ります。**
/// 打った直後にはがすと、**削除のあとに保存が届いて付箋が復活**します。
///
/// **同じ付箋への保留は 1 つだけ持ちます（あとから来たものが勝ち）。** 削除は保存を追い越し、
/// 一度消したら以後の保存は捨てます。
///
/// [DebouncedMemoRepositoryInfrastructure](DebouncedMemoRepositoryInfrastructure.swift)
/// と同じ役割ですが、**再試行は持ちません。** 付箋は雛形を参照するだけの小さなレコードで、
/// 失敗しても次の打鍵で丸ごと上書きされます。
nonisolated final class SerializedStickyNoteRepositoryInfrastructure: StickyNoteRepositoryProtocol {
    private enum Mutation {
        case upsert(StickyNote)
        case delete
    }

    private struct State {
        /// 付箋ごとの、まだ書けていない最新の変更。
        var pending: [StickyNote.ID: Mutation] = [:]
        /// 書き込みの鎖の末尾。次の書き込みはこれの完了を待ちます。
        var tail: Task<Void, Never>?
    }

    private let base: any StickyNoteRepositoryProtocol
    private let state = Mutex(State())

    init(wrapping base: any StickyNoteRepositoryProtocol) {
        self.base = base
    }

    func loadStickyNotes() throws -> [StickyNote] {
        try base.loadStickyNotes()
    }

    func save(_ note: StickyNote) async throws {
        enqueue(.upsert(note), for: note.id)
    }

    func delete(id: StickyNote.ID) async throws {
        enqueue(.delete, for: id)
    }

    /// 保留している書き込みを確定する。**アプリ終了時に呼びます。**
    func flush() async throws {
        await state.withLock { $0.tail }?.value
        try await base.flush()
    }

    // MARK: -

    private func enqueue(_ mutation: Mutation, for id: StickyNote.ID) {
        let previous = state.withLock { state -> Task<Void, Never>? in
            state.pending[id] = mutation

            return state.tail
        }

        let task = Task { [weak self] in
            // **前の書き込みを待ってから始めます。** 同じファイルへ同時に書かないためです。
            await previous?.value

            guard let self else {
                return
            }

            await drain(id: id)
        }

        state.withLock { $0.tail = task }
    }

    private func drain(id: StickyNote.ID) async {
        // **取り出すときに最新だけを見ます。** 待っている間に来た変更で上書きされていれば、
        // 途中の値は書かずに飛ばします。
        guard let mutation = state.withLock({ $0.pending.removeValue(forKey: id) }) else {
            return
        }

        do {
            switch mutation {
            case let .upsert(note):
                try await base.save(note)
            case .delete:
                try await base.delete(id: id)
            }
        } catch {
            // **握り潰します。** 付箋は次の打鍵で丸ごと書き直されるので、
            // 途中の失敗を持ち回る意味がありません。
        }
    }
}
