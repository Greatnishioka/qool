import Foundation
import Testing
@testable import qool

/// [DebouncedMemoRepository](../qool/Infrastructure/Persistence/DebouncedMemoRepository.swift) の検証。
///
/// **書き込みが遅れる仕組みなので、失われる条件も明示的にテストします。**
@MainActor
struct DebouncedMemoRepositoryTests {
    /// 書き込み回数を数える土台。
    private final class CountingMemoRepository: MemoRepository {
        private var storage: [Memo] = []
        private(set) var saveCallCount = 0
        private(set) var deleteCallCount = 0

        func loadMemos() -> [Memo] {
            storage.sorted { $0.updatedAt > $1.updatedAt }
        }

        func save(_ memo: Memo) {
            saveCallCount += 1

            if let index = storage.firstIndex(where: { $0.id == memo.id }) {
                storage[index] = memo
            } else {
                storage.append(memo)
            }
        }

        func delete(id: Memo.ID) {
            deleteCallCount += 1
            storage.removeAll { $0.id == id }
        }
    }

    /// テストが時間に依存しないよう、既定では十分長い間隔にして `flush()` で確定させます。
    private func makeRepository(
        interval: Duration = .seconds(30)
    ) -> (DebouncedMemoRepository, CountingMemoRepository) {
        let base = CountingMemoRepository()

        return (DebouncedMemoRepository(wrapping: base, interval: interval), base)
    }

    // MARK: - まとめ書き

    @Test func 保存直後はまだ書き込まれない() {
        let (repository, base) = makeRepository()

        repository.save(Memo(title: "下書き"))

        #expect(base.saveCallCount == 0)
    }

    @Test func 連続した保存が一度にまとまる() {
        let (repository, base) = makeRepository()
        var memo = Memo(title: "初期")

        // スライダーのドラッグ相当。
        for index in 0..<60 {
            memo.title = "編集 \(index)"
            repository.save(memo)
        }
        repository.flush()

        #expect(base.saveCallCount == 1, "60 回の保存が 1 回の書き込みになる")
        #expect(base.loadMemos().first?.title == "編集 59", "最後の内容が残る")
    }

    @Test func 別々のメモはそれぞれ書き込まれる() {
        let (repository, base) = makeRepository()

        repository.save(Memo(title: "A"))
        repository.save(Memo(title: "B"))
        repository.flush()

        #expect(base.saveCallCount == 2)
    }

    @Test func 一定時間が過ぎれば自動で書き込まれる() async throws {
        let (repository, base) = makeRepository(interval: .milliseconds(50))

        repository.save(Memo(title: "自動"))
        #expect(base.saveCallCount == 0)

        try await Task.sleep(for: .milliseconds(400))

        #expect(base.saveCallCount == 1)
    }

    // MARK: - 未書き込みの内容が見えること

    @Test func 書き込み前でも読み出せる() throws {
        let (repository, base) = makeRepository()
        let memo = Memo(title: "未書き込み")

        repository.save(memo)

        // 書いていないから見えない、という状態を外から観測させない。
        #expect(base.loadMemos().isEmpty)
        #expect(repository.loadMemos().map(\.title) == ["未書き込み"])
    }

    @Test func 保留中の内容が土台の内容を上書きして見える() throws {
        let (repository, base) = makeRepository()
        var memo = Memo(title: "確定済み")
        repository.save(memo)
        repository.flush()

        memo.title = "編集中"
        repository.save(memo)

        #expect(base.loadMemos().map(\.title) == ["確定済み"])
        #expect(repository.loadMemos().map(\.title) == ["編集中"])
        #expect(repository.loadMemos().count == 1, "二重に現れない")
    }

    @Test func 読み出しは更新日時の降順になる() {
        let (repository, _) = makeRepository()
        let now = Date()

        repository.save(Memo(title: "古い", updatedAt: now.addingTimeInterval(-3600)))
        repository.save(Memo(title: "新しい", updatedAt: now))

        #expect(repository.loadMemos().map(\.title) == ["新しい", "古い"])
    }

    // MARK: - 削除

    @Test func 保留中のメモを削除すると復活しない() {
        let (repository, base) = makeRepository()
        let memo = Memo(title: "消す")

        repository.save(memo)
        repository.delete(id: memo.id)
        repository.flush()

        #expect(base.loadMemos().isEmpty, "flush で書き戻されてはいけない")
        #expect(repository.loadMemos().isEmpty)
    }

    // MARK: - flush

    @Test func flushは保留がなければ何もしない() {
        let (repository, base) = makeRepository()

        repository.flush()
        repository.flush()

        #expect(base.saveCallCount == 0)
    }

    @Test func flush後の保存は再び保留される() {
        let (repository, base) = makeRepository()
        var memo = Memo(title: "一度目")

        repository.save(memo)
        repository.flush()
        #expect(base.saveCallCount == 1)

        memo.title = "二度目"
        repository.save(memo)
        #expect(base.saveCallCount == 1, "まだ書かれない")

        repository.flush()
        #expect(base.saveCallCount == 2)
    }

    /// **既知の制約。** flush せずに破棄すると保留分は失われます。
    /// これを避けるため、アプリ終了時とパネルを閉じるときに `flush()` を呼んでいます。
    @Test func flushせずに破棄すると保留分は失われる() {
        let base = CountingMemoRepository()

        do {
            let repository = DebouncedMemoRepository(wrapping: base, interval: .seconds(30))
            repository.save(Memo(title: "失われる"))
        }

        #expect(base.saveCallCount == 0)
        #expect(base.loadMemos().isEmpty)
    }
}
