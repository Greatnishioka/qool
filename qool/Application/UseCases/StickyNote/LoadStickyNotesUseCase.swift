nonisolated struct LoadStickyNotesUseCase {
    let repository: any StickyNoteRepositoryProtocol

    func callAsFunction() throws -> [StickyNote] {
        try repository.loadStickyNotes()
    }
}
