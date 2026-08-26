import CoreGraphics
import Foundation
import Testing
@testable import qool

/// [FileMemoRepository](../qool/Infrastructure/Persistence/FileMemoRepository.swift) の検証。
/// 実際のファイルシステムを使い、テストごとに一時ディレクトリを作って捨てます。
struct FileMemoRepositoryTests {
    /// 一時ディレクトリを用意し、処理の後で必ず片付ける。
    private func withTemporaryRepository(
        _ body: (FileMemoRepository, URL) throws -> Void
    ) throws {
        let root = URL.temporaryDirectory.appending(
            path: "qool-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try body(FileMemoRepository(rootDirectory: root), root)
    }

    private func memo(title: String, updatedAt: Date = Date()) -> Memo {
        Memo(
            title: title,
            updatedAt: updatedAt,
            canvas: Canvas(elements: [
                CanvasElement(
                    kind: .rectangle,
                    frame: CGRect(x: 10, y: 20, width: 100, height: 50),
                    fillColor: .paper
                ),
                CanvasElement(
                    kind: .text,
                    frame: CGRect(x: 15, y: 25, width: 80, height: 30),
                    fillColor: .clear,
                    showsStroke: false,
                    text: "本文"
                )
            ])
        )
    }

    // MARK: -

    @Test func 保存していないうちは空を返す() throws {
        try withTemporaryRepository { repository, _ in
            #expect(repository.loadMemos().isEmpty)
        }
    }

    @Test func 保存したメモを読み戻せる() throws {
        try withTemporaryRepository { repository, _ in
            let original = memo(title: "買い物メモ")
            repository.save(original)

            let loaded = repository.loadMemos()

            #expect(loaded.count == 1)
            #expect(loaded.first?.id == original.id)
            #expect(loaded.first?.title == original.title)
            #expect(loaded.first?.canvas == original.canvas)
        }
    }

    @Test func 更新日時はミリ秒まで保たれる() throws {
        try withTemporaryRepository { repository, _ in
            let original = memo(title: "日時")
            repository.save(original)

            let loaded = try #require(repository.loadMemos().first)
            let difference = abs(loaded.updatedAt.timeIntervalSince(original.updatedAt))

            // ISO8601 のミリ秒表記なので、それより下は丸められます。
            #expect(difference < 0.001)
        }
    }

    @Test func 同じIDで保存すると上書きされる() throws {
        try withTemporaryRepository { repository, _ in
            var original = memo(title: "初版")
            repository.save(original)

            original.title = "改訂版"
            repository.save(original)

            let loaded = repository.loadMemos()

            #expect(loaded.count == 1)
            #expect(loaded.first?.title == "改訂版")
        }
    }

    @Test func 更新日時の新しい順に並ぶ() throws {
        try withTemporaryRepository { repository, _ in
            let now = Date()
            repository.save(memo(title: "古い", updatedAt: now.addingTimeInterval(-3600)))
            repository.save(memo(title: "新しい", updatedAt: now))
            repository.save(memo(title: "中間", updatedAt: now.addingTimeInterval(-60)))

            #expect(repository.loadMemos().map(\.title) == ["新しい", "中間", "古い"])
        }
    }

    @Test func 削除するとファイルごと消える() throws {
        try withTemporaryRepository { repository, root in
            let target = memo(title: "消す")
            repository.save(target)
            repository.save(memo(title: "残す"))

            repository.delete(id: target.id)

            #expect(repository.loadMemos().map(\.title) == ["残す"])

            let directory = root
                .appending(path: "memos", directoryHint: .isDirectory)
                .appending(path: target.id.uuidString, directoryHint: .isDirectory)
            #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
        }
    }

    @Test func 存在しないメモを削除しても落ちない() throws {
        try withTemporaryRepository { repository, _ in
            repository.delete(id: UUID())

            #expect(repository.loadMemos().isEmpty)
        }
    }

    @Test func 壊れたメモがあっても他のメモは読める() throws {
        try withTemporaryRepository { repository, root in
            repository.save(memo(title: "無事"))

            // 1 メモ = 1 ディレクトリなので、被害は該当メモだけに留まるはず。
            let brokenDirectory = root
                .appending(path: "memos", directoryHint: .isDirectory)
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: brokenDirectory, withIntermediateDirectories: true)
            try Data("これは JSON ではありません".utf8)
                .write(to: brokenDirectory.appending(path: "memo.json"))

            #expect(repository.loadMemos().map(\.title) == ["無事"])
        }
    }

    @Test func 未知のスキーマ版は読み飛ばす() throws {
        try withTemporaryRepository { repository, root in
            repository.save(memo(title: "無事"))

            let futureDirectory = root
                .appending(path: "memos", directoryHint: .isDirectory)
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: futureDirectory, withIntermediateDirectories: true)
            let json = """
            {
              "schemaVersion": \(FileMemoRepository.schemaVersion + 1),
              "memo": {
                "id": "\(UUID().uuidString)",
                "title": "未来のメモ",
                "updatedAt": "2030-01-01T00:00:00.000Z",
                "canvas": { "elements": [] }
              }
            }
            """
            try Data(json.utf8).write(to: futureDirectory.appending(path: "memo.json"))

            // 新しい版のファイルは読まずに残す。古いアプリが上書きして壊さないため。
            #expect(repository.loadMemos().map(\.title) == ["無事"])
        }
    }

    @Test func 保存したJSONは人が読める() throws {
        try withTemporaryRepository { repository, root in
            let target = memo(title: "読める")
            repository.save(target)

            let fileURL = root
                .appending(path: "memos", directoryHint: .isDirectory)
                .appending(path: target.id.uuidString, directoryHint: .isDirectory)
                .appending(path: "memo.json")
            let text = try String(contentsOf: fileURL, encoding: .utf8)

            #expect(text.contains("\"schemaVersion\" : \(FileMemoRepository.schemaVersion)"))
            #expect(text.contains("\"title\" : \"読める\""))
            #expect(text.contains("\"updatedAt\""))
            // 日時が数値ではなく ISO8601 の文字列であること。
            #expect(text.contains("T"))
        }
    }
}
