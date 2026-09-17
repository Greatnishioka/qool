import Foundation
import Synchronization

/// 付箋の書き込みを**順番どおりに**行う。
///
/// 本文は 1 打鍵ごと、位置はドラッグのたびに保存されます。素のまま投げると
/// **完了の順番が入れ替わり、古い本文が最後に書かれて巻き戻ります。**
///
/// **同じ付箋への保留は 1 つだけ持ちます（あとから来たものが勝ち）。**
/// **一度消した付箋への保存は捨てます。** 打った直後にはがすと、
/// 遅れて届いた保存がファイルを作り直し、再起動で付箋が復活するためです。
///
/// [DebouncedMemoRepositoryInfrastructure](DebouncedMemoRepositoryInfrastructure.swift)
/// と同じ役割ですが、**時間を置いた再試行は持ちません。** 付箋は小さなレコードで、
/// 失敗しても `flush()` でもう一度書き、それでも駄目なら**投げて呼び出し側に伝えます。**
nonisolated final class SerializedStickyNoteRepositoryInfrastructure: StickyNoteRepositoryProtocol {
    enum WriteError: Error {
        /// 書けなかった付箋が残っている。**終了してよいかの判断に使います。**
        case unsaved(count: Int)
    }

    private enum Mutation {
        case upsert(StickyNote)
        case delete
    }

    private struct State {
        /// 付箋ごとの、まだ書けていない最新の変更。
        var pending: [StickyNote.ID: Mutation] = [:]
        /// 消した付箋。**以後の保存を捨てるために覚えます。**
        ///
        /// 消しません。id は UUID なので使い回されず、増え方も人が消した回数どまりです。
        var deleted: Set<StickyNote.ID> = []
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
    ///
    /// **書けなかったものが残っていれば投げます。** 握り潰すと、終了してよいかの
    /// 判断が「書けている」と嘘をつき、**最後の変更を失ったまま終了します。**
    func flush() async throws {
        await state.withLock { $0.tail }?.value

        // **失敗した分をもう一度だけ書きます。** 終了時は次の打鍵が来ません。
        for id in state.withLock({ Array($0.pending.keys) }) {
            await drain(id: id)
        }

        try await base.flush()

        let unsaved = state.withLock { $0.pending.count }

        guard unsaved == 0 else {
            throw WriteError.unsaved(count: unsaved)
        }
    }

    // MARK: -

    private func enqueue(_ mutation: Mutation, for id: StickyNote.ID) {
        // **鎖の取り出しと付け替えを 1 回のロックで行います。** 分けると、
        // 同時に入ってきた 2 つが同じ末尾を掴んで**鎖が枝分かれ**し、
        // `flush()` が片方しか待てません。
        state.withLock { state in
            switch mutation {
            case .delete:
                state.deleted.insert(id)
                state.pending[id] = .delete

            case .upsert:
                guard !state.deleted.contains(id) else {
                    return
                }

                state.pending[id] = mutation
            }

            let previous = state.tail

            state.tail = Task { [weak self] in
                // **前の書き込みを待ってから始めます。** 同じファイルへ同時に書かないためです。
                await previous?.value
                await self?.drain(id: id)
            }
        }
    }

    private func drain(id: StickyNote.ID) async {
        // **取り出すときに最新だけを見ます。** 待っている間に来た変更で上書きされていれば、
        // 途中の値は書かずに飛ばします。
        guard let mutation = state.withLock({ $0.pending[id] }) else {
            return
        }

        do {
            switch mutation {
            case let .upsert(note):
                try await base.save(note)
            case .delete:
                try await base.delete(id: id)
            }

            // **書けてから消します。** 先に消すと、失敗したときに何を書き損ねたか分かりません。
            // 待っている間に新しい変更が来ていたら、そちらは残します。
            state.withLock { state in
                guard case .upsert(let written)? = state.pending[id], case .upsert(let target) = mutation else {
                    state.pending.removeValue(forKey: id)

                    return
                }

                if written == target {
                    state.pending.removeValue(forKey: id)
                }
            }
        } catch {
            // **保留に残します。** `flush()` がもう一度書き、それでも駄目なら投げます。
        }
    }
}
