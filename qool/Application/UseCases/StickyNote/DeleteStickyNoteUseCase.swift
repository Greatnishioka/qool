nonisolated struct DeleteStickyNoteUseCase {
    let repository: any StickyNoteRepositoryProtocol

    func callAsFunction(id: StickyNote.ID) async throws {
        try await repository.delete(id: id)
    }
}
