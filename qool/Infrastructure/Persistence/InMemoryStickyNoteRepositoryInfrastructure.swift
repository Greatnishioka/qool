import Foundation
import Synchronization

/// テストとプレビュー用。可変状態は `Mutex` で守ります。
///
/// **`bootstrap` の既定値はこちらです。** ディスクの実装を既定にしていたせいで、
/// **テストを流すと実際の付箋が消える**経路ができていました
/// （偽のメモ一覧に無い付箋を孤児とみなして削除していた）。
/// 危ない既定値は置きません。
nonisolated final class InMemoryStickyNoteRepositoryInfrastructure: StickyNoteRepositoryProtocol {
    private let notes: Mutex<[StickyNote]>

    init(seedNotes: [StickyNote] = []) {
        notes = Mutex(seedNotes)
    }

    func loadStickyNotes() throws -> [StickyNote] {
        notes.withLock { $0.sorted { $0.updatedAt > $1.updatedAt } }
    }

    func save(_ note: StickyNote) async throws {
        notes.withLock { notes in
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = note
            } else {
                notes.append(note)
            }
        }
    }

    func delete(id: StickyNote.ID) async throws {
        notes.withLock { $0.removeAll { $0.id == id } }
    }
}
