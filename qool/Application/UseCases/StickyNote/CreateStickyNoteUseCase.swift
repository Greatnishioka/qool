import CoreGraphics

/// 雛形から付箋を 1 枚出す。
///
/// **本文は引き継ぎません。** 空のまま出し、雛形の本文をそのまま見せます。
/// 2 枚目に 1 枚目の内容が入っていると、複製したのか新しく出したのか分かりません
/// （[#29](https://github.com/Greatnishioka/qool/issues/29)）。
nonisolated struct CreateStickyNoteUseCase {
    let repository: any StickyNoteRepositoryProtocol

    func callAsFunction(
        from template: Memo,
        at origin: CGPoint
    ) async throws -> StickyNote {
        let note = StickyNote(
            templateID: template.id,
            title: template.title,
            origin: origin
        )
        try await repository.save(note)

        return note
    }
}
