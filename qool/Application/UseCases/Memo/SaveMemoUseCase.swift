import Foundation

nonisolated struct SaveMemoUseCase {
    let repository: any MemoRepositoryProtocol

    /// 保存した内容を返す。
    ///
    /// `updatedAt` をここで更新するため、**呼び出し元が持っているメモは保存直後に古くなります。**
    /// 一覧は更新日時の降順で並ぶので、戻り値で置き換えないと並び順が壊れます。
    @discardableResult
    func callAsFunction(_ memo: Memo) async throws -> Memo {
        var updatedMemo = memo
        updatedMemo.updatedAt = Date()
        try await repository.save(updatedMemo)

        return updatedMemo
    }
}
