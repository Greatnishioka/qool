/// メモ本体とは別に持つ設定。
///
/// **メモの保存（`MemoRepositoryProtocol`）とは分けています。** 小さく、単一で、
/// 頻繁に読まない値なので、ファイル分割やまとめ書きの仕組みが要りません。
@MainActor
protocol AppSettingsProtocol: AnyObject {
    var hotKeyConfiguration: HotKeyConfiguration { get set }

    /// `⌃⇧Q → F` で出すメモ。**メモ側にフラグを持たせていないのは、
    /// 付け替えのたびに旧メインの書き込みも要るため**です。指すのは 1 つなのでここに置きます。
    var mainMemoID: Memo.ID? { get set }
}
