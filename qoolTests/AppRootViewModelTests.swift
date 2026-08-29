import Foundation
import Synchronization
import Testing
@testable import qool

/// [AppRootViewModel](../qool/Presentation/ViewModels/AppRootViewModel.swift) の検証。
///
/// 主眼は「**保存のたびに全件読み直していない**」ことの確認です。
/// 以前は `saveMemo` が `reload()` を呼んでおり、1 件の書き込みに対して
/// 全メモの読み込みと復号が走っていました。
@MainActor
struct AppRootViewModelTests {
    /// 呼び出し回数を数えるリポジトリ。
    private final class CountingMemoRepository: MemoRepository {
        private struct State {
            var storage: [Memo]
            var loadCallCount = 0
            var saveCallCount = 0
            /// true にすると保存が必ず失敗します。エラー表示の検証用。
            var failsToSave = false
            var failsToLoad = false
        }

        private let state: Mutex<State>

        var loadCallCount: Int { state.withLock(\.loadCallCount) }
        var saveCallCount: Int { state.withLock(\.saveCallCount) }

        init(memos: [Memo] = []) {
            state = Mutex(State(storage: memos))
        }

        func setFailsToSave(_ fails: Bool) {
            state.withLock { $0.failsToSave = fails }
        }

        func setFailsToLoad(_ fails: Bool) {
            state.withLock { $0.failsToLoad = fails }
        }

        func loadMemos() throws -> [Memo] {
            try state.withLock { state in
                state.loadCallCount += 1

                if state.failsToLoad {
                    throw TestError.failed
                }

                return state.storage.sorted { $0.updatedAt > $1.updatedAt }
            }
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
            state.withLock { $0.storage.removeAll { $0.id == id } }
        }
    }

    private enum TestError: Error {
        case failed
    }

    private func makeViewModel(
        repository: CountingMemoRepository
    ) -> AppRootViewModel {
        AppRootViewModel.bootstrap(repository: repository)
    }

    // MARK: - 読み込み回数

    @Test func 起動時に一度だけ全件読み込む() async throws {
        let repository = CountingMemoRepository()
        _ = makeViewModel(repository: repository)

        #expect(repository.loadCallCount == 1)
    }

    @Test func 保存しても全件読み込みは走らない() async throws {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)
        let memo = try #require(await viewModel.createMemo())

        for index in 0..<20 {
            var edited = memo
            edited.title = "編集 \(index)"
            await viewModel.saveMemo(edited)
        }

        // 起動時の 1 回だけ。20 回の保存で増えないこと。
        #expect(repository.loadCallCount == 1)
        #expect(repository.saveCallCount == 21, "新規作成 1 回 + 保存 20 回")
    }

    // MARK: - 一覧への反映

    @Test func 新規作成したメモが一覧に載る() async throws {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)

        let memo = try #require(await viewModel.createMemo())

        #expect(viewModel.memos.map(\.id) == [memo.id])
        #expect(viewModel.selectedMemo?.id == memo.id)
    }

    @Test func 保存した内容が一覧に反映される() async throws {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)
        var memo = try #require(await viewModel.createMemo())

        memo.title = "改訂版"
        await viewModel.saveMemo(memo)

        #expect(viewModel.memos.count == 1, "置き換えであって追加ではない")
        #expect(viewModel.memos.first?.title == "改訂版")
    }

    @Test func 保存で更新日時が新しくなる() async throws {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)
        let memo = try #require(await viewModel.createMemo())
        let original = memo.updatedAt

        await viewModel.saveMemo(memo)

        let saved = try #require(viewModel.memos.first)
        // 引数の memo をそのまま一覧へ入れていると、ここが等しくなってしまう。
        #expect(saved.updatedAt > original)
        #expect(viewModel.selectedMemo?.updatedAt == saved.updatedAt)
    }

    @Test func 保存したメモが一覧の先頭へ来る() async throws {
        let now = Date()
        let older = Memo(title: "古い", updatedAt: now.addingTimeInterval(-3600))
        let newer = Memo(title: "新しい", updatedAt: now)
        let repository = CountingMemoRepository(memos: [older, newer])
        let viewModel = makeViewModel(repository: repository)

        #expect(viewModel.memos.map(\.title) == ["新しい", "古い"])

        await viewModel.saveMemo(older)

        // 更新日時の降順。ディスクから読み直さずに並べ替えられていること。
        #expect(viewModel.memos.map(\.title) == ["古い", "新しい"])
    }

    @Test func 要素の追加が保存され一覧に反映される() async throws {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)
        _ = await viewModel.createMemo()

        await viewModel.addElement(using: .rectangle)

        #expect(viewModel.selectedMemo?.canvas.elements.count == 1)
        #expect(viewModel.memos.first?.canvas.elements.count == 1)
        #expect(repository.loadCallCount == 1)
    }

    @Test func 選択中のメモがなければ要素を追加しない() async throws {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)

        await viewModel.addElement(using: .rectangle)

        #expect(viewModel.memos.isEmpty)
        #expect(repository.saveCallCount == 0)
    }

    // MARK: - 失敗の扱い
    //
    // 状態表示の検証は PersistenceIntegrationTests へ移しました。
    // ここで偽リポジトリを直接渡すと、本番の DebouncedMemoRepository を通らないため
    // 「テストは通るが実機では表示されない」状態を見逃します（実際に見逃しました）。

    @Test func 保存が成功していれば何も表示しない() async throws {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)

        _ = await viewModel.createMemo()

        #expect(viewModel.persistenceStatus == .ok)
        #expect(!viewModel.didFailToLoad)
    }

    @Test func 保存に失敗しても編集内容は画面に残る() async throws {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)
        var memo = try #require(await viewModel.createMemo())

        repository.setFailsToSave(true)
        memo.title = "失敗しても残る"
        await viewModel.saveMemo(memo)

        // ディスクには書けていないが、操作を巻き戻すと編集が消えたように見えます。
        #expect(viewModel.memos.first?.title == "失敗しても残る")
        #expect(viewModel.selectedMemo?.title == "失敗しても残る")
    }

    @Test func 読み込みに失敗しても一覧を空にしない() async throws {
        let now = Date()
        let repository = CountingMemoRepository(memos: [Memo(title: "既存", updatedAt: now)])
        let viewModel = makeViewModel(repository: repository)

        repository.setFailsToLoad(true)
        viewModel.reload()

        // 空にすると「メモが 0 件」と区別できません。
        #expect(viewModel.didFailToLoad)
        #expect(viewModel.memos.map(\.title) == ["既存"])
    }

    @Test func 読み込みが成功すれば失敗表示は消える() async throws {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)

        repository.setFailsToLoad(true)
        viewModel.reload()
        #expect(viewModel.didFailToLoad)

        repository.setFailsToLoad(false)
        viewModel.reload()

        #expect(!viewModel.didFailToLoad)
    }

    @Test func reloadは明示的に呼べば全件読み直す() async throws {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)

        viewModel.reload()

        #expect(repository.loadCallCount == 2)
    }
}
