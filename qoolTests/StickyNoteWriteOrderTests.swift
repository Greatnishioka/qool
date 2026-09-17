import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import qool

/// 付箋の書き込みが**付箋ごとに直列化される**ことの検証。
///
/// 本文は 1 打鍵ごと、位置はドラッグのたびに保存されます。
/// 完了の順番が入れ替わると、古い本文が最後に書かれて巻き戻ります。
struct StickyNoteWriteOrderTests {
    /// 書き込みの完了順を遅らせられる土台。
    private final class SlowRepository: StickyNoteRepositoryProtocol, @unchecked Sendable {
        private let state = Mutex<(notes: [StickyNote], log: [String], delay: Duration)>(([], [], .zero))

        var notes: [StickyNote] { state.withLock { $0.notes } }
        var log: [String] { state.withLock { $0.log } }

        func setDelay(_ delay: Duration) { state.withLock { $0.delay = delay } }

        func loadStickyNotes() throws -> [StickyNote] { notes }

        func save(_ note: StickyNote) async throws {
            let delay = state.withLock { $0.delay }
            try? await Task.sleep(for: delay)

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
            state.withLock { state in
                state.log.append("delete")
                state.notes.removeAll { $0.id == id }
            }
        }
    }

    private func note(id: UUID, title: String) -> StickyNote {
        StickyNote(id: id, templateID: UUID(), title: title, origin: .zero)
    }

    /// **後から出した保存が勝ちます。** 途中の値は書かずに飛ばします。
    @Test func 保存の順番が入れ替わらない() async throws {
        let base = SlowRepository()
        let repository = SerializedStickyNoteRepositoryInfrastructure(wrapping: base)
        let id = UUID()

        base.setDelay(.milliseconds(30))
        try await repository.save(note(id: id, title: "A"))
        base.setDelay(.zero)
        try await repository.save(note(id: id, title: "AB"))

        try await repository.flush()

        #expect(base.notes.first?.title == "AB")
    }

    /// **消したあとに保存が届いても復活させません。**
    @Test func 削除のあとの保存で復活しない() async throws {
        let base = SlowRepository()
        let repository = SerializedStickyNoteRepositoryInfrastructure(wrapping: base)
        let id = UUID()

        base.setDelay(.milliseconds(30))
        try await repository.save(note(id: id, title: "打った直後"))
        try await repository.delete(id: id)

        try await repository.flush()

        #expect(base.notes.isEmpty)
    }

    /// **`flush` は書き終わるまで待ちます。** 待たないと、終了時に最後の 1 打鍵が消えます。
    @Test func flushは書き終わるまで待つ() async throws {
        let base = SlowRepository()
        let repository = SerializedStickyNoteRepositoryInfrastructure(wrapping: base)

        base.setDelay(.milliseconds(30))
        try await repository.save(note(id: UUID(), title: "さいご"))

        try await repository.flush()

        #expect(base.notes.count == 1)
    }

    /// 別々の付箋は互いを待ちません（同じファイルではないため）。
    @Test func 別の付箋も取りこぼさない() async throws {
        let base = SlowRepository()
        let repository = SerializedStickyNoteRepositoryInfrastructure(wrapping: base)

        try await repository.save(note(id: UUID(), title: "いちまい"))
        try await repository.save(note(id: UUID(), title: "にまい"))

        try await repository.flush()

        #expect(base.notes.count == 2)
    }
}
