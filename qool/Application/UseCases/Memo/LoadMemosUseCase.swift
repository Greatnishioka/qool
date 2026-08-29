nonisolated struct LoadMemosUseCase {
    let repository: any MemoRepositoryProtocol

    func callAsFunction() throws -> [Memo] {
        try repository.loadMemos()
    }
}
