import Foundation

/// 画像アセットの保管庫。**まだ実装がありません。**
///
/// `CanvasElement` は画像の実体ではなく `UUID` を持ちます。`Memo` は値型で編集のたびに
/// 丸ごとコピー・比較されるため、画像を入れると 1px 動かすたびに画像のコピーが走ります。
nonisolated protocol ImageAssetRepositoryProtocol {
    /// 保存されている画像のバイト列。存在しなければ `nil`。
    func data(for id: UUID) -> Data?

    /// 画像を保存し、割り当てた ID を返す。
    @discardableResult
    func save(_ data: Data) throws -> UUID

    func delete(id: UUID)
}
