import Foundation
import Synchronization
import Testing
@testable import qool

/// [DebouncedMemoRepository](../qool/Infrastructure/Persistence/DebouncedMemoRepository.swift) の検証。
///
/// **書き込みが遅れる仕組みなので、失われる条件も明示的にテストします。**
@MainActor
struct DebouncedMemoRepositoryTests {
    /// 書き込み回数を数える土台。
    private final class CountingMemoRepository: MemoRepository {
        private struct State {
            var storage: [Memo] = []
            var saveCallCount = 0
            var deleteCallCount = 0
            /// true にすると保存が必ず失敗します。再試行の検証用。
            var failsToSave = false
        }

        private let state = Mutex(State())

        var saveCallCount: Int { state.withLock(\.saveCallCount) }
        var deleteCallCount: Int { state.withLock(\.deleteCallCount) }

        func setFailsToSave(_ fails: Bool) {
            state.withLock { $0.failsToSave = fails }
        }

        func loadMemos() throws -> [Memo] {
            state.withLock { $0.storage.sorted { $0.updatedAt > $1.updatedAt } }
        }

        func save(_ memo: Memo) async throws {
            try state.withLock { state in
                state.saveCallCount += 1

                if state.failsToSave {
                    throw TestError.failed
                }

                if let index = state.storage.firstIndex(where: { $0.id == memo.id }) {
                    state.storage[index] = memo
                } else {
                    state.storage.append(memo)
                }
            }
        }

        func delete(id: Memo.ID) async throws {
            state.withLock { state in
                state.deleteCallCount += 1
                state.storage.removeAll { $0.id == id }
            }
        }
    }

    private enum TestError: Error {
        case failed
    }

    /// テストが時間に依存しないよう、既定では十分長い間隔にして `flush()` で確定させます。
    private func makeRepository(
        interval: Duration = .seconds(30)
    ) -> (DebouncedMemoRepository, CountingMemoRepository) {
        let base = CountingMemoRepository()

        return (DebouncedMemoRepository(wrapping: base, interval: interval), base)
    }

    // MARK: - まとめ書き

    @Test func 保存直後はまだ書き込まれない() async throws {
        let (repository, base) = makeRepository()

        try await repository.save(Memo(title: "下書き"))

        #expect(base.saveCallCount == 0)
    }

    @Test func 連続した保存が一度にまとまる() async throws {
        let (repository, base) = makeRepository()
        var memo = Memo(title: "初期")

        // スライダーのドラッグ相当。
        for index in 0..<60 {
            memo.title = "編集 \(index)"
            try await repository.save(memo)
        }
        try await repository.flush()

        #expect(base.saveCallCount == 1, "60 回の保存が 1 回の書き込みになる")
        try #expect(base.loadMemos().first?.title == "編集 59", "最後の内容が残る")
    }

    @Test func 別々のメモはそれぞれ書き込まれる() async throws {
        let (repository, base) = makeRepository()

        try await repository.save(Memo(title: "A"))
        try await repository.save(Memo(title: "B"))
        try await repository.flush()

        #expect(base.saveCallCount == 2)
    }

    @Test func 一定時間が過ぎれば自動で書き込まれる() async throws {
        let (repository, base) = makeRepository(interval: .milliseconds(50))

        try await repository.save(Memo(title: "自動"))
        #expect(base.saveCallCount == 0)

        try await Task.sleep(for: .milliseconds(400))

        #expect(base.saveCallCount == 1)
    }

    // MARK: - 未書き込みの内容が見えること

    @Test func 書き込み前でも読み出せる() async throws {
        let (repository, base) = makeRepository()
        let memo = Memo(title: "未書き込み")

        try await repository.save(memo)

        // 書いていないから見えない、という状態を外から観測させない。
        try #expect(base.loadMemos().isEmpty)
        try #expect(repository.loadMemos().map(\.title) == ["未書き込み"])
    }

    @Test func 保留中の内容が土台の内容を上書きして見える() async throws {
        let (repository, base) = makeRepository()
        var memo = Memo(title: "確定済み")
        try await repository.save(memo)
        try await repository.flush()

        memo.title = "編集中"
        try await repository.save(memo)

        try #expect(base.loadMemos().map(\.title) == ["確定済み"])
        try #expect(repository.loadMemos().map(\.title) == ["編集中"])
        try #expect(repository.loadMemos().count == 1, "二重に現れない")
    }

    @Test func 読み出しは更新日時の降順になる() async throws {
        let (repository, _) = makeRepository()
        let now = Date()

        try await repository.save(Memo(title: "古い", updatedAt: now.addingTimeInterval(-3600)))
        try await repository.save(Memo(title: "新しい", updatedAt: now))

        try #expect(repository.loadMemos().map(\.title) == ["新しい", "古い"])
    }

    // MARK: - 削除

    @Test func 保留中のメモを削除すると復活しない() async throws {
        let (repository, base) = makeRepository()
        let memo = Memo(title: "消す")

        try await repository.save(memo)
        try await repository.delete(id: memo.id)
        try await repository.flush()

        try #expect(base.loadMemos().isEmpty, "flush で書き戻されてはいけない")
        try #expect(repository.loadMemos().isEmpty)
    }

    // MARK: - flush

    @Test func flushは保留がなければ何もしない() async throws {
        let (repository, base) = makeRepository()

        try await repository.flush()
        try await repository.flush()

        #expect(base.saveCallCount == 0)
    }

    @Test func flush後の保存は再び保留される() async throws {
        let (repository, base) = makeRepository()
        var memo = Memo(title: "一度目")

        try await repository.save(memo)
        try await repository.flush()
        #expect(base.saveCallCount == 1)

        memo.title = "二度目"
        try await repository.save(memo)
        #expect(base.saveCallCount == 1, "まだ書かれない")

        try await repository.flush()
        #expect(base.saveCallCount == 2)
    }

    // MARK: - 失敗したときの再試行

    @Test func 書き込みに失敗するとflushが投げる() async throws {
        let (repository, base) = makeRepository()
        base.setFailsToSave(true)

        try await repository.save(Memo(title: "失敗する"))

        await #expect(throws: (any Error).self) {
            try await repository.flush()
        }
    }

    @Test func 失敗した書き込みは保留に戻る() async throws {
        let (repository, base) = makeRepository()
        base.setFailsToSave(true)
        let memo = Memo(title: "戻る")

        try await repository.save(memo)
        try? await repository.flush()

        // 保留へ戻っているので、読み出しからは見え続けます。
        try #expect(repository.loadMemos().map(\.title) == ["戻る"])
    }

    @Test func 失敗後に復旧すれば書き込まれる() async throws {
        let (repository, base) = makeRepository()
        base.setFailsToSave(true)

        try await repository.save(Memo(title: "あとで成功"))
        try? await repository.flush()
        try #expect(base.loadMemos().isEmpty)

        base.setFailsToSave(false)
        try await repository.flush()

        try #expect(base.loadMemos().map(\.title) == ["あとで成功"])
    }

    /// **既知の制約。** flush せずに破棄すると保留分は失われます。
    /// これを避けるため、アプリ終了時とパネルを閉じるときに `flush()` を呼んでいます。
    @Test func flushせずに破棄すると保留分は失われる() async throws {
        let base = CountingMemoRepository()

        do {
            let repository = DebouncedMemoRepository(wrapping: base, interval: .seconds(30))
            try await repository.save(Memo(title: "失われる"))
        }

        #expect(base.saveCallCount == 0)
        try #expect(base.loadMemos().isEmpty)
    }
}
