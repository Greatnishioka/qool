import Foundation

/// 画像アセットの保管庫。
///
/// `CanvasElement` は画像の実体を持たず `UUID` だけを持ちます
/// （[永続化方針](../../../docs/architecture/persistence.md)の「モデル側の持ち方」）。
/// `Memo` は `Equatable` / `Hashable` な値型で、`CanvasViewModel` の `@Published var memo` は
/// 編集のたびに丸ごとコピー・比較されるため、ここに画像が入ると
/// 図形を 1px 動かすたびに画像のコピーと比較が走ります。
///
/// `NSImage` ではなく `Data` を扱うのは、Domain を UI フレームワークから独立させるためです。
/// 画像型への変換は Presentation / Infrastructure の責務になります。
protocol ImageAssetRepository {
    /// 保存されている画像のバイト列。存在しなければ `nil`。
    func data(for id: UUID) -> Data?

    /// 画像を保存し、割り当てた ID を返す。
    @discardableResult
    func save(_ data: Data) throws -> UUID

    func delete(id: UUID)
}
