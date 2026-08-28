import Foundation
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
        private var storage: [Memo]
        private(set) var loadCallCount = 0
        private(set) var saveCallCount = 0

        init(memos: [Memo] = []) {
            storage = memos
        }

        func loadMemos() -> [Memo] {
            loadCallCount += 1

            return storage.sorted { $0.updatedAt > $1.updatedAt }
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
            storage.removeAll { $0.id == id }
        }
    }

    private func makeViewModel(
        repository: CountingMemoRepository
    ) -> AppRootViewModel {
        AppRootViewModel.bootstrap(repository: repository)
    }

    // MARK: - 読み込み回数

    @Test func 起動時に一度だけ全件読み込む() {
        let repository = CountingMemoRepository()
        _ = makeViewModel(repository: repository)

        #expect(repository.loadCallCount == 1)
    }

    @Test func 保存しても全件読み込みは走らない() {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)
        let memo = viewModel.createMemo()

        for index in 0..<20 {
            var edited = memo
            edited.title = "編集 \(index)"
            viewModel.saveMemo(edited)
        }

        // 起動時の 1 回だけ。20 回の保存で増えないこと。
        #expect(repository.loadCallCount == 1)
        #expect(repository.saveCallCount == 21, "新規作成 1 回 + 保存 20 回")
    }

    // MARK: - 一覧への反映

    @Test func 新規作成したメモが一覧に載る() {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)

        let memo = viewModel.createMemo()

        #expect(viewModel.memos.map(\.id) == [memo.id])
        #expect(viewModel.selectedMemo?.id == memo.id)
    }

    @Test func 保存した内容が一覧に反映される() {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)
        var memo = viewModel.createMemo()

        memo.title = "改訂版"
        viewModel.saveMemo(memo)

        #expect(viewModel.memos.count == 1, "置き換えであって追加ではない")
        #expect(viewModel.memos.first?.title == "改訂版")
    }

    @Test func 保存で更新日時が新しくなる() throws {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)
        let memo = viewModel.createMemo()
        let original = memo.updatedAt

        viewModel.saveMemo(memo)

        let saved = try #require(viewModel.memos.first)
        // 引数の memo をそのまま一覧へ入れていると、ここが等しくなってしまう。
        #expect(saved.updatedAt > original)
        #expect(viewModel.selectedMemo?.updatedAt == saved.updatedAt)
    }

    @Test func 保存したメモが一覧の先頭へ来る() throws {
        let now = Date()
        let older = Memo(title: "古い", updatedAt: now.addingTimeInterval(-3600))
        let newer = Memo(title: "新しい", updatedAt: now)
        let repository = CountingMemoRepository(memos: [older, newer])
        let viewModel = makeViewModel(repository: repository)

        #expect(viewModel.memos.map(\.title) == ["新しい", "古い"])

        viewModel.saveMemo(older)

        // 更新日時の降順。ディスクから読み直さずに並べ替えられていること。
        #expect(viewModel.memos.map(\.title) == ["古い", "新しい"])
    }

    @Test func 要素の追加が保存され一覧に反映される() throws {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)
        _ = viewModel.createMemo()

        viewModel.addElement(using: .rectangle)

        #expect(viewModel.selectedMemo?.canvas.elements.count == 1)
        #expect(viewModel.memos.first?.canvas.elements.count == 1)
        #expect(repository.loadCallCount == 1)
    }

    @Test func 選択中のメモがなければ要素を追加しない() {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)

        viewModel.addElement(using: .rectangle)

        #expect(viewModel.memos.isEmpty)
        #expect(repository.saveCallCount == 0)
    }

    @Test func reloadは明示的に呼べば全件読み直す() {
        let repository = CountingMemoRepository()
        let viewModel = makeViewModel(repository: repository)

        viewModel.reload()

        #expect(repository.loadCallCount == 2)
    }
}
