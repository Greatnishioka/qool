import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import qool

/// 付箋の書き込みが**順番どおりに行われる**ことの検証。
///
/// 本文は 1 打鍵ごと、位置はドラッグのたびに保存されます。
/// 完了の順番が入れ替わると、古い本文が最後に書かれて巻き戻ります。
struct StickyNoteWriteOrderTests {
    /// 書き込みを**合図があるまで止められる**土台。
    ///
    /// **時間で待ちません。** `sleep` で間合いを作ると、負荷の高い環境で
    /// 「まだ始まっていない」ことになり、不定期に落ちます
    /// （[#18](https://github.com/Greatnishioka/qool/issues/18) で踏みました）。
    private final class GatedRepository: StickyNoteRepositoryProtocol, @unchecked Sendable {
        private struct State {
            var notes: [StickyNote] = []
            var log: [String] = []
            var fails = false
        }

        /// **開いているかと待ち行列を 1 つのロックで持ちます。** 分けると、
        /// 「閉じている」と判断してから行列に入るまでの間に開かれ、
        /// **取りこぼして永久に待ちます。**
        private struct Gate {
            var isOpen = true
            var waiting: [CheckedContinuation<Void, Never>] = []
        }

        private let state = Mutex(State())
        private let gate = Mutex(Gate())

        var notes: [StickyNote] { state.withLock { $0.notes } }
        var log: [String] { state.withLock { $0.log } }

        func closeGate() { gate.withLock { $0.isOpen = false } }
        func setFails(_ fails: Bool) { state.withLock { $0.fails = fails } }

        func openGate() {
            let waiting = gate.withLock { gate -> [CheckedContinuation<Void, Never>] in
                gate.isOpen = true
                let waiting = gate.waiting
                gate.waiting = []

                return waiting
            }

            for continuation in waiting {
                continuation.resume()
            }
        }

        private func waitForGate() async {
            await withCheckedContinuation { continuation in
                let isOpen = gate.withLock { gate -> Bool in
                    guard !gate.isOpen else {
                        return true
                    }

                    gate.waiting.append(continuation)

                    return false
                }

                if isOpen {
                    continuation.resume()
                }
            }
        }

        func loadStickyNotes() throws -> [StickyNote] { notes }

        func save(_ note: StickyNote) async throws {
            await waitForGate()

            if state.withLock({ $0.fails }) {
                throw CocoaError(.fileWriteNoPermission)
            }

            state.withLock { state in
                state.log.append("save:\(note.title)")

                if let index = state.notes.firstIndex(where: { $0.id == note.id }) {
                    state.notes[index] = note
                } else {
                    state.notes.append(note)
                }
            }
        }

        func delete(id: StickyNote.ID) async throws {
            await waitForGate()

            state.withLock { state in
                state.log.append("delete")
                state.notes.removeAll { $0.id == id }
            }
        }
    }

    private func note(id: UUID, title: String) -> StickyNote {
        StickyNote(id: id, templateID: UUID(), title: title, origin: .zero)
    }

    // MARK: - 順番

    /// **後から出した保存が勝ちます。** 途中の値は書かずに飛ばします。
    @Test func 保存の順番が入れ替わらない() async throws {
        let base = GatedRepository()
        let repository = SerializedStickyNoteRepositoryInfrastructure(wrapping: base)
        let id = UUID()

        base.closeGate()
        try await repository.save(note(id: id, title: "A"))
        try await repository.save(note(id: id, title: "AB"))
        base.openGate()

        try await repository.flush()

        #expect(base.notes.first?.title == "AB")
    }

    /// **消したあとに保存が届いても復活させません。**
    @Test func 削除のあとの保存で復活しない() async throws {
        let base = GatedRepository()
        let repository = SerializedStickyNoteRepositoryInfrastructure(wrapping: base)
        let id = UUID()

        try await repository.save(note(id: id, title: "打った"))
        try await repository.flush()

        try await repository.delete(id: id)
        try await repository.flush()

        // 削除が済んだあとに、遅れていた保存が届く。
        try await repository.save(note(id: id, title: "遅れて届いた"))
        try await repository.flush()

        #expect(base.notes.isEmpty)
    }

    /// 削除より先に出した保存が、まだ書けていない場合。
    @Test func 保存より削除が後でも復活しない() async throws {
        let base = GatedRepository()
        let repository = SerializedStickyNoteRepositoryInfrastructure(wrapping: base)
        let id = UUID()

        base.closeGate()
        try await repository.save(note(id: id, title: "打った直後"))
        try await repository.delete(id: id)
        base.openGate()

        try await repository.flush()

        #expect(base.notes.isEmpty)
    }

    // MARK: - flush

    /// **`flush` は書き終わるまで待ちます。** 待たないと、終了時に最後の 1 打鍵が消えます。
    @Test func flushは書き終わるまで待つ() async throws {
        let base = GatedRepository()
        let repository = SerializedStickyNoteRepositoryInfrastructure(wrapping: base)

        try await repository.save(note(id: UUID(), title: "さいご"))
        try await repository.flush()

        #expect(base.notes.count == 1)
    }

    /// **書けなければ投げます。** 握り潰すと、終了してよいかの判断が嘘をつきます。
    @Test func 書けなければflushが投げる() async throws {
        let base = GatedRepository()
        let repository = SerializedStickyNoteRepositoryInfrastructure(wrapping: base)

        base.setFails(true)
        try await repository.save(note(id: UUID(), title: "書けない"))

        await #expect(throws: (any Error).self) {
            try await repository.flush()
        }
    }

    /// 失敗したあとに書けるようになれば、`flush` で書き切れます。
    @Test func 失敗してもflushで書き直せる() async throws {
        let base = GatedRepository()
        let repository = SerializedStickyNoteRepositoryInfrastructure(wrapping: base)

        base.setFails(true)
        try await repository.save(note(id: UUID(), title: "あとで書ける"))
        try? await repository.flush()

        base.setFails(false)
        try await repository.flush()

        #expect(base.notes.count == 1)
    }

    /// 複数の付箋を取りこぼしません。**鎖が枝分かれすると片方しか待てません。**
    @Test func 別の付箋も取りこぼさない() async throws {
        let base = GatedRepository()
        let repository = SerializedStickyNoteRepositoryInfrastructure(wrapping: base)

        base.closeGate()

        for index in 1...8 {
            try await repository.save(note(id: UUID(), title: "\(index) まい目"))
        }

        base.openGate()
        try await repository.flush()

        #expect(base.notes.count == 8)
    }
}
