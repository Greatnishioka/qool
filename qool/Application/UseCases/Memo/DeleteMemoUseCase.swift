nonisolated struct DeleteMemoUseCase {
    let repository: any MemoRepositoryProtocol

    func callAsFunction(_ id: Memo.ID) async throws {
        try await repository.delete(id: id)
    }
}
