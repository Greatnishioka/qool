nonisolated struct CreateMemoUseCase {
    let repository: any MemoRepositoryProtocol

    func callAsFunction() async throws -> Memo {
        let memo = Memo(title: "新規メモ")
        try await repository.save(memo)

        return memo
    }
}
