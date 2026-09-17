import Foundation

/// `Sendable` を要求するのは、書き込みが呼び出し元のアクタを離れて実行されるためです
/// （[MemoRepositoryProtocol](MemoRepositoryProtocol.swift) と同じ理由）。
nonisolated protocol StickyNoteRepositoryProtocol: Sendable {
    /// 全付箋を読み出す。個々の失敗は読み飛ばすが、**一覧そのものを取得できない場合は投げる**。
    ///
    /// **同期のままにしています。** 非同期にすると `AppRootViewModel.init` から呼べません。
    func loadStickyNotes() throws -> [StickyNote]

    func save(_ note: StickyNote) async throws

    func delete(id: StickyNote.ID) async throws
}
