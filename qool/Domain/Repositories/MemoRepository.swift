import Foundation

nonisolated protocol MemoRepository {
    func loadMemos() -> [Memo]
    func save(_ memo: Memo)
    func delete(id: Memo.ID)

    /// 保留している書き込みを確定する。
    ///
    /// 書き込みを遅らせる実装（[DebouncedMemoRepository](../../Infrastructure/Persistence/DebouncedMemoRepository.swift)）の
    /// ためにあります。**アプリ終了時とパネルを閉じるときに必ず呼ぶ必要があります。**
    /// 即座に書く実装では何もしません。
    func flush()
}

nonisolated extension MemoRepository {
    func flush() {}
}
