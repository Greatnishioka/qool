import Foundation

nonisolated struct SaveMemoUseCase {
    let repository: any MemoRepositoryProtocol

    /// 保存した内容を返す。`updatedAt` をここで更新するため、
    /// **戻り値で置き換えないと一覧の並び順（更新日時の降順）が壊れます。**
    @discardableResult
    func callAsFunction(_ memo: Memo) async throws -> Memo {
        var updatedMemo = memo
        updatedMemo.updatedAt = Date()
        try await repository.save(updatedMemo)

        return updatedMemo
    }
}
