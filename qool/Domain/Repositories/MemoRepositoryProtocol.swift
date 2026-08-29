import Foundation

/// `Sendable` を要求するのは、書き込みが呼び出し元のアクタを離れて実行されるためです。
nonisolated protocol MemoRepositoryProtocol: Sendable {
    /// 全メモを読み出す。個々の失敗は読み飛ばすが、**一覧そのものを取得できない場合は投げる**
    /// （「0 件」と「読み込めなかった」を呼び出し元が区別できるように）。
    ///
    /// **同期のままにしています。** 非同期にすると `AppRootViewModel.init` から呼べません。
    func loadMemos() throws -> [Memo]

    /// メモを保存する。失敗したら投げる。
    /// 伝えないと、画面には編集後の内容が残ったままディスクには書かれていない状態に気づけません。
    func save(_ memo: Memo) async throws

    func delete(id: Memo.ID) async throws

    /// 保留している書き込みを確定する。**アプリ終了時に必ず呼ぶ必要があります。**
    /// 即座に書く実装では何もしません。
    func flush() async throws
}

nonisolated extension MemoRepositoryProtocol {
    func flush() async throws {}
}
