import Foundation

struct LoadMemosUseCase {
    var repository: MemoRepository

    func execute() -> [Memo] {
        repository.loadMemos()
    }
}

struct CreateMemoUseCase {
    var repository: MemoRepository

    func execute() -> Memo {
        let memo = Memo(title: "新規メモ")
        repository.save(memo)
        return memo
    }
}

struct SaveMemoUseCase {
    var repository: MemoRepository

    func execute(_ memo: Memo) {
        var updatedMemo = memo
        updatedMemo.updatedAt = Date()
        repository.save(updatedMemo)
    }
}
