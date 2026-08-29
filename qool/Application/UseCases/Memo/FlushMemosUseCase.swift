/// 保留している書き込みを確定する。
///
/// アプリ終了時とパネルを閉じるときに実行しないと、
/// [まとめ書き](../../../Infrastructure/Persistence/DebouncedMemoRepositoryInfrastructure.swift)の分が失われます。
nonisolated struct FlushMemosUseCase {
    let repository: any MemoRepositoryProtocol

    func callAsFunction() async throws {
        try await repository.flush()
    }
}
