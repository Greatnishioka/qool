import Foundation
import Synchronization
import Testing
@testable import qool

/// **本番と同じ構成**（`DebouncedMemoRepository` を挟む）での検証。
///
/// 偽のリポジトリを `AppRootViewModel` へ直接渡すテストは、まとめ書きを通らないため
/// 「単体テストは通るが実機では動かない」状態を見逃します。実際に見逃したので、
/// 失敗の扱いはここで固定します。
@MainActor
struct PersistenceIntegrationTests {
    /// 失敗を切り替えられる土台。
    private final class ControllableRepository: MemoRepository {
        private struct State {
            var storage: [Memo] = []
            var failsToSave = false
            var failsToDelete = false
            /// この ID の保存だけ失敗させる。
            var failingID: Memo.ID?
            var saveCallCount = 0
            /// 保存を意図的に遅らせて、順序の入れ替わりを再現するためのもの。
            var saveDelay: Duration = .zero
        }

        private let state = Mutex(State())

        /// `base.save` に**実際に入った**ことを知らせます。
        /// 固定時間の `sleep` で待つと、負荷の高い環境で「まだ始まっていない」ことに
        /// 気づけず、直列化が壊れていてもテストが通ってしまいます。
        let saveEntries: AsyncStream<Memo.ID>
        private let saveEntryContinuation: AsyncStream<Memo.ID>.Continuation

        init() {
            let (stream, continuation) = AsyncStream.makeStream(of: Memo.ID.self)
            saveEntries = stream
            saveEntryContinuation = continuation
        }

        var saveCallCount: Int { state.withLock(\.saveCallCount) }
        var stored: [Memo] { state.withLock(\.storage) }

        func setFailsToSave(_ fails: Bool) { state.withLock { $0.failsToSave = fails } }
        func setFailsToDelete(_ fails: Bool) { state.withLock { $0.failsToDelete = fails } }
        func setFailingID(_ id: Memo.ID?) { state.withLock { $0.failingID = id } }
        func setSaveDelay(_ delay: Duration) { state.withLock { $0.saveDelay = delay } }

        func loadMemos() throws -> [Memo] {
            state.withLock { $0.storage.sorted { $0.updatedAt > $1.updatedAt } }
        }

        func save(_ memo: Memo) async throws {
            let (fails, delay) = state.withLock { state -> (Bool, Duration) in
                state.saveCallCount += 1
                let fails = state.failsToSave || state.failingID == memo.id
                return (fails, state.saveDelay)
            }

            saveEntryContinuation.yield(memo.id)

            if delay > .zero {
                try? await Task.sleep(for: delay)
            }

            if fails {
                throw TestError.failed
            }

            state.withLock { state in
                if let index = state.storage.firstIndex(where: { $0.id == memo.id }) {
                    state.storage[index] = memo
                } else {
                    state.storage.append(memo)
                }
            }
        }

        func delete(id: Memo.ID) async throws {
            if state.withLock(\.failsToDelete) {
                throw TestError.failed
            }

            state.withLock { $0.storage.removeAll { $0.id == id } }
        }
    }

    private enum TestError: Error { case failed }

    /// リトライのバックオフ（500ms + 1s）を待ち切れる長さ。
    private static let retryWindow = Duration.seconds(4)

    private func makeStack(
        interval: Duration = .milliseconds(20)
    ) -> (AppRootViewModel, DebouncedMemoRepository, ControllableRepository) {
        let base = ControllableRepository()
        let debounced = DebouncedMemoRepository(wrapping: base, interval: interval)
        let viewModel = AppRootViewModel.bootstrap(repository: debounced, monitor: debounced)

        return (viewModel, debounced, base)
    }

    /// 状態が期待どおりになるまで待つ。監視は非同期に届くため。
    private func waitForStatus(
        _ expected: AppRootViewModel.PersistenceStatus,
        in viewModel: AppRootViewModel,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            if viewModel.persistenceStatus == expected {
                return true
            }

            try? await Task.sleep(for: .milliseconds(20))
        }

        return viewModel.persistenceStatus == expected
    }

    // MARK: - 失敗が UI へ届くこと

    @Test func 書き込みに失敗すると画面の状態が変わる() async throws {
        let (viewModel, _, base) = makeStack()
        let memo = try #require(await viewModel.createMemo())

        base.setFailsToSave(true)
        await viewModel.saveMemo(memo)

        // 以前はここが .ok のままで、バナーが一度も出ませんでした。
        #expect(await waitForStatus(.failing, in: viewModel, timeout: Self.retryWindow))
    }

    @Test func 書き込みが成功すれば状態は正常へ戻る() async throws {
        let (viewModel, _, base) = makeStack()
        let memo = try #require(await viewModel.createMemo())

        base.setFailsToSave(true)
        await viewModel.saveMemo(memo)
        #expect(await waitForStatus(.failing, in: viewModel, timeout: Self.retryWindow))

        base.setFailsToSave(false)
        _ = await viewModel.flush()

        #expect(await waitForStatus(.ok, in: viewModel))
    }

    @Test func 失敗しても編集内容は画面に残る() async throws {
        let (viewModel, _, base) = makeStack()
        var memo = try #require(await viewModel.createMemo())

        base.setFailsToSave(true)
        memo.title = "失敗しても残る"
        await viewModel.saveMemo(memo)

        #expect(viewModel.memos.first?.title == "失敗しても残る")
    }

    // MARK: - 順序

    @Test func 古い保存が新しい保存を上書きしない() async throws {
        let (_, repository, base) = makeStack(interval: .milliseconds(10))
        var entries = base.saveEntries.makeAsyncIterator()
        var memo = Memo(title: "v1")

        // 1 件目の書き込みを遅くして、2 件目と重なる状況を作る。
        base.setSaveDelay(.milliseconds(300))
        try await repository.save(memo)

        // 実際に base.save へ入ったことを確認してから次を投入する。
        _ = await entries.next()

        memo.title = "v2"
        try await repository.save(memo)

        base.setSaveDelay(.zero)
        try await repository.flush()

        // 直列化されていなければ v1 が後から書かれて巻き戻ります。
        #expect(base.stored.map(\.title) == ["v2"])
    }

    @Test func 保存の途中で削除しても復活しない() async throws {
        let (_, repository, base) = makeStack(interval: .milliseconds(10))
        var entries = base.saveEntries.makeAsyncIterator()
        let memo = Memo(title: "消える")

        base.setSaveDelay(.milliseconds(300))
        try await repository.save(memo)

        _ = await entries.next()

        try await repository.delete(id: memo.id)

        base.setSaveDelay(.zero)
        try await repository.flush()

        #expect(base.stored.isEmpty, "削除したメモが書き戻されてはいけない")
    }

    @Test func 失敗した保存の後に削除しても復活しない() async throws {
        let (_, repository, base) = makeStack(interval: .milliseconds(10))
        let memo = Memo(title: "復活しない")

        // 保存を失敗させてから削除する。ジョブを積む設計だと、
        // 再投入された save が delete を追い越して復活します。
        base.setFailsToSave(true)
        try await repository.save(memo)
        try? await Task.sleep(for: .milliseconds(100))

        base.setFailsToSave(false)
        try await repository.delete(id: memo.id)
        try await repository.flush()

        #expect(base.stored.isEmpty)
    }

    // MARK: - リトライ

    @Test func リトライは有限回で止まる() async throws {
        let (_, repository, base) = makeStack(interval: .milliseconds(10))
        base.setFailsToSave(true)

        try await repository.save(Memo(title: "失敗し続ける"))
        try? await Task.sleep(for: Self.retryWindow)

        let countAfterGivingUp = base.saveCallCount
        try? await Task.sleep(for: .seconds(1))

        // 上限に達した後は増えないこと。無限リトライだとここで増えます。
        #expect(base.saveCallCount == countAfterGivingUp)
        #expect(countAfterGivingUp <= 3, "上限は 3 回")
    }

    @Test func 上限に達しても内容は保持され手動再試行で復帰する() async throws {
        let (viewModel, _, base) = makeStack(interval: .milliseconds(10))
        let memo = try #require(await viewModel.createMemo())

        base.setFailsToSave(true)
        await viewModel.saveMemo(memo)
        #expect(await waitForStatus(.failing, in: viewModel, timeout: Self.retryWindow))

        base.setFailsToSave(false)
        await viewModel.retryFailedWork()

        #expect(await waitForStatus(.ok, in: viewModel))
        #expect(base.stored.contains { $0.id == memo.id })
    }

    @Test func 一件の失敗が他のメモの保存を塞がない() async throws {
        let (_, repository, base) = makeStack(interval: .milliseconds(10))
        let broken = Memo(title: "書けないメモ")
        let healthy = Memo(title: "書けるメモ")

        // 1 メモ = 1 ディレクトリなので、ID 単位の失敗は現実に起こります。
        base.setFailingID(broken.id)
        try await repository.save(broken)
        try await repository.save(healthy)
        try? await repository.flush()
        try? await Task.sleep(for: Self.retryWindow)

        // 失敗で drain 全体を抜けていると、正常なメモも永久に書かれません。
        #expect(base.stored.contains { $0.id == healthy.id })
        #expect(!base.stored.contains { $0.id == broken.id })
    }

    @Test func 諦めた後に別のdrainが積まれても再試行しない() async throws {
        let (_, repository, base) = makeStack(interval: .milliseconds(10))
        let broken = Memo(title: "書けないメモ")
        base.setFailingID(broken.id)

        try await repository.save(broken)
        try? await Task.sleep(for: Self.retryWindow)

        let countAfterGivingUp = base.saveCallCount
        #expect(countAfterGivingUp <= 3, "同じ内容への自動リトライは 3 回まで（実際: \(countAfterGivingUp)）")

        // 別のメモを保存して drain をもう 1 本積む。
        // 試行回数を drain のローカルに持っていると、ここで諦めた分がまた 3 回試されます。
        try await repository.save(Memo(title: "別のメモ"))
        try? await Task.sleep(for: Self.retryWindow)

        #expect(base.saveCallCount == countAfterGivingUp + 1, "増えるのは別メモの 1 回だけ")
    }

    // MARK: - flush の契約

    @Test func flushは書けなければ失敗を返す() async throws {
        let (viewModel, _, base) = makeStack(interval: .seconds(30))
        let memo = try #require(await viewModel.createMemo())

        base.setFailsToSave(true)
        await viewModel.saveMemo(memo)

        // 終了してよいかの判断に使うため、書けていないなら false。
        #expect(await viewModel.flush() == false)
    }

    @Test func flushは書けていれば成功を返す() async throws {
        let (viewModel, _, _) = makeStack(interval: .seconds(30))
        let memo = try #require(await viewModel.createMemo())

        await viewModel.saveMemo(memo)

        #expect(await viewModel.flush() == true)
    }

    @Test func 未書き込みの内容も一覧から見える() async throws {
        let (_, repository, base) = makeStack(interval: .seconds(30))
        let memo = Memo(title: "未書き込み")

        try await repository.save(memo)

        #expect(try base.loadMemos().isEmpty)
        #expect(try repository.loadMemos().map(\.title) == ["未書き込み"])
    }
}
