import Foundation

nonisolated struct SaveStickyNoteUseCase {
    let repository: any StickyNoteRepositoryProtocol

    /// 保存した内容を返す。`updatedAt` をここで更新するため、
    /// **戻り値で置き換えないと一覧の並び順（更新日時の降順）が壊れます。**
    @discardableResult
    func callAsFunction(_ note: StickyNote) async throws -> StickyNote {
        var updated = note
        updated.updatedAt = Date()
        try await repository.save(updated)

        return updated
    }
}
