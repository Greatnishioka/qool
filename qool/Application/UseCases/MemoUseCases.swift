import Foundation

/// 保留している書き込みを確定する。
///
/// アプリ終了時とパネルを閉じるときに実行しないと、
/// [まとめ書き](../../Infrastructure/Persistence/DebouncedMemoRepository.swift)の分が失われます。
struct FlushMemosUseCase {
    var repository: MemoRepository

    func execute() {
        repository.flush()
    }
}

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

    /// 保存した内容を返す。
    ///
    /// `updatedAt` をここで更新するため、**呼び出し元が持っているメモは保存直後に古くなります。**
    /// 一覧は更新日時の降順で並ぶので、戻り値で置き換えないと並び順が壊れます。
    @discardableResult
    func execute(_ memo: Memo) -> Memo {
        var updatedMemo = memo
        updatedMemo.updatedAt = Date()
        repository.save(updatedMemo)

        return updatedMemo
    }
}
