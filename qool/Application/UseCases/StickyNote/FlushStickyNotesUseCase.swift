nonisolated struct FlushStickyNotesUseCase {
    let repository: any StickyNoteRepositoryProtocol

    func callAsFunction() async throws {
        try await repository.flush()
    }
}
