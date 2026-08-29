/// 保留している書き込みを確定する。アプリ終了時に実行しないと、まとめ書きの分が失われます。
nonisolated struct FlushMemosUseCase {
    let repository: any MemoRepositoryProtocol

    func callAsFunction() async throws {
        try await repository.flush()
    }
}
