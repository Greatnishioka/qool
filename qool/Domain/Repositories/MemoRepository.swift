import Foundation

protocol MemoRepository {
    func loadMemos() -> [Memo]
    func save(_ memo: Memo)
    func delete(id: Memo.ID)
}
