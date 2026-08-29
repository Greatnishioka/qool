import Foundation

/// `Sendable` を要求するのは、実装が実行文脈をまたいで共有されるためです。
/// 書き込みは呼び出し元のアクタを離れて実行されます。
nonisolated protocol MemoRepositoryProtocol: Sendable {
    /// 全メモを読み出す。
    ///
    /// **同期のままにしています。** 起動時に一度しか呼ばれず、`memo.json` は画像を含まないため
    /// 軽量です。非同期にすると `AppRootViewModel.init` から呼べなくなり、
    /// 「一瞬空のパネルが出てから埋まる」ためのローディング状態が必要になります。
    ///
    /// 個々のメモの読み込み失敗は読み飛ばしますが、**一覧そのものを取得できない場合は投げます。**
    /// 「メモが 0 件」と「読み込めなかった」を呼び出し元が区別できるようにするためです。
    func loadMemos() throws -> [Memo]

    /// メモを保存する。失敗したら投げる。
    ///
    /// 呼び出し元へ失敗を伝えないと、画面には編集後の内容が残ったまま
    /// ディスクには書かれていない、という状態に気づけません。
    func save(_ memo: Memo) async throws

    func delete(id: Memo.ID) async throws

    /// 保留している書き込みを確定する。
    ///
    /// 書き込みを遅らせる実装（[DebouncedMemoRepositoryInfrastructure](../../Infrastructure/Persistence/DebouncedMemoRepositoryInfrastructure.swift)）の
    /// ためにあります。**アプリ終了時とパネルを閉じるときに必ず呼ぶ必要があります。**
    /// 即座に書く実装では何もしません。
    func flush() async throws
}

nonisolated extension MemoRepositoryProtocol {
    func flush() async throws {}
}
