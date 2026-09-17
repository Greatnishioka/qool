/// 雛形を消したときに、その雛形から出した付箋も片付ける。
///
/// **残すと形のない付箋になります。** 付箋は形を持たないので、
/// 雛形が消えると描きようがありません。
nonisolated struct DeleteStickyNotesOfTemplateUseCase {
    let repository: any StickyNoteRepositoryProtocol

    /// - Returns: 消した付箋の id。呼び出し側が一覧から外すために使います。
    @discardableResult
    func callAsFunction(
        templateID: Memo.ID,
        in notes: [StickyNote]
    ) async throws -> [StickyNote.ID] {
        let targets = notes.filter { $0.templateID == templateID }.map(\.id)

        for id in targets {
            try await repository.delete(id: id)
        }

        return targets
    }
}
