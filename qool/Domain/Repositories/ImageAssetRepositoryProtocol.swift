import Foundation

/// 画像アセットの保管庫。
///
/// `CanvasElement` は画像の実体ではなく `UUID` を持ちます。`Memo` は値型で編集のたびに
/// 丸ごとコピー・比較されるため、画像を入れると 1px 動かすたびに画像のコピーが走ります。
///
/// **アセットはメモに属します。** [レイアウト](../../../docs/architecture/persistence.md#レイアウト案)が
/// `memos/<memo-uuid>/assets/` である以上、どのメモのものかを指定しないと場所が決まりません。
/// メモを消せばアセットも一緒に消える、という性質もここから来ています。
///
/// `NSImage` ではなく `Data` を扱うのは、Domain を UI フレームワークから独立させるためです。
/// **バイト列は PNG であることを前提にしています**（保存先の拡張子が `.png` に固定されているため）。
nonisolated protocol ImageAssetRepositoryProtocol: Sendable {
    /// 保存されている画像のバイト列。存在しなければ `nil`。
    func data(for id: UUID, in memoID: Memo.ID) -> Data?

    /// 画像を保存し、割り当てた ID を返す。
    @discardableResult
    func save(_ data: Data, in memoID: Memo.ID) throws -> UUID

    /// 存在しないものの削除は成功として扱います。
    func delete(id: UUID, in memoID: Memo.ID) throws
}
