import Foundation
import Testing
@testable import qool

/// 付箋をディスクへ置いて読み戻す検証。
///
/// **壊れた 1 件で一覧全体を落とさないこと**が要点です。
struct StickyNoteStorageTests {
    private func withTemporaryRepository(
        _ body: (FileStickyNoteRepositoryInfrastructure, URL) async throws -> Void
    ) async throws {
        let root = URL.temporaryDirectory.appending(
            path: "qool-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

        defer { try? FileManager.default.removeItem(at: root) }

        try await body(FileStickyNoteRepositoryInfrastructure(rootDirectory: root), root)
    }

    /// **端数のない日時にします。** 保存の形式は ISO8601 のミリ秒までで、
    /// それ自体は意図した仕様です。ただし `1_700_000_000.123` のような値は
    /// `Double` で正確に表せず、**丸めると `.122` になって往復で一致しません。**
    /// テストの値がずれているだけなので、秒ちょうどを使います。
    private func note(
        templateID: UUID = UUID(),
        title: String = "付箋",
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> StickyNote {
        StickyNote(
            templateID: templateID,
            title: title,
            origin: CGPoint(x: 120, y: 340),
            texts: [UUID(): "ほんぶん"],
            updatedAt: updatedAt
        )
    }

    @Test func 保存して読み戻せる() async throws {
        try await withTemporaryRepository { repository, _ in
            let original = note()
            try await repository.save(original)

            let loaded = try repository.loadStickyNotes()

            #expect(loaded.count == 1)
            #expect(loaded.first == original)
        }
    }

    /// **一度も出していなければディレクトリがありません。** これは失敗ではありません。
    @Test func 一度も出していなければ空を返す() async throws {
        try await withTemporaryRepository { repository, _ in
            let loaded = try repository.loadStickyNotes()

            #expect(loaded.isEmpty)
        }
    }

    @Test func 消せる() async throws {
        try await withTemporaryRepository { repository, _ in
            let target = note()
            try await repository.save(target)
            try await repository.save(note())

            try await repository.delete(id: target.id)

            let loaded = try repository.loadStickyNotes()

            #expect(loaded.count == 1)
            #expect(!loaded.contains { $0.id == target.id })
        }
    }

    /// 存在しないものの削除は成功として扱います。
    @Test func 無いものを消しても投げない() async throws {
        try await withTemporaryRepository { repository, _ in
            try await repository.delete(id: UUID())
        }
    }

    /// **壊れた 1 件は読み飛ばします。** 一覧全体が開けなくなるほうが困ります。
    @Test func 壊れた付箋は読み飛ばす() async throws {
        try await withTemporaryRepository { repository, root in
            let healthy = note()
            try await repository.save(healthy)

            let broken = root.appending(path: "notes/\(UUID().uuidString).json")
            try Data("こわれています".utf8).write(to: broken)

            let loaded = try repository.loadStickyNotes()

            #expect(loaded.count == 1)
            #expect(loaded.first?.id == healthy.id)
        }
    }

    /// **ファイル名と中身の id が食い違うものは信じません。**
    /// 手でコピーしたファイルが混ざると、削除の効かない付箋ができます。
    @Test func idがファイル名と違えば読み飛ばす() async throws {
        try await withTemporaryRepository { repository, root in
            let target = note()
            try await repository.save(target)

            let original = root.appending(path: "notes/\(target.id.uuidString).json")
            let renamed = root.appending(path: "notes/\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: original, to: renamed)

            let loaded = try repository.loadStickyNotes()

            #expect(loaded.isEmpty)
        }
    }

    @Test func 更新日時の新しい順に並ぶ() async throws {
        try await withTemporaryRepository { repository, _ in
            var older = note(title: "ふるい")
            older.updatedAt = Date(timeIntervalSince1970: 1000)
            var newer = note(title: "あたらしい")
            newer.updatedAt = Date(timeIntervalSince1970: 2000)

            try await repository.save(older)
            try await repository.save(newer)

            let loaded = try repository.loadStickyNotes()

            #expect(loaded.first?.title == "あたらしい")
        }
    }
}
