import CoreGraphics

/// 雛形から付箋を 1 枚出す。
///
/// **本文は引き継ぎません。** 空のまま出し、雛形の本文をそのまま見せます。
/// 2 枚目に 1 枚目の内容が入っていると、複製したのか新しく出したのか分かりません
/// （[#29](https://github.com/Greatnishioka/qool/issues/29)）。
nonisolated struct CreateStickyNoteUseCase {
    let repository: any StickyNoteRepositoryProtocol

    /// - Parameter existing: 既に出ている付箋。**題名に連番を振る**ために見ます。
    func callAsFunction(
        from template: Memo,
        at origin: CGPoint,
        existing: [StickyNote]
    ) async throws -> StickyNote {
        let note = StickyNote(
            templateID: template.id,
            title: Self.title(for: template, existing: existing),
            origin: origin
        )
        try await repository.save(note)

        return note
    }

    /// 出したばかりの付箋の題名。
    ///
    /// **同じ雛形から何枚でも出せるので、雛形の題名だけでは見分けられません。**
    /// 2 枚目からは番号を足します。
    ///
    /// **空いている一番小さい番号を使います。** 枚数で決めると、間の 1 枚を
    /// はがしたあとに同じ番号が 2 つ並びます。
    static func title(for template: Memo, existing: [StickyNote]) -> String {
        let used = Set(existing.filter { $0.templateID == template.id }.map(\.title))

        guard used.contains(template.title) else {
            return template.title
        }

        var number = 2

        while used.contains("\(template.title) \(number)") {
            number += 1
        }

        return "\(template.title) \(number)"
    }
}
