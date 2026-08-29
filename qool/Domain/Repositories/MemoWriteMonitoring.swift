import Foundation

/// 書き込みの状態。
///
/// 個々の保存の成否ではなく、**リポジトリが集約した状態**を表します。
/// 1 件ずつの結果を流すと、別のメモの成功で「未保存が残っているのに正常」と
/// 表示してしまうためです。
nonisolated enum MemoWriteState: Equatable, Sendable {
    /// 未保存の変更が 1 件も残っていない。**これ以外は何か書けていません。**
    case idle
    /// 書き込みに失敗し、再試行している。
    case retrying(attempt: Int)
    /// 再試行の上限に達した。**未保存の内容は保持されており、手動で再試行できます。**
    case failed
}

/// 書き込み状態を通知する。
///
/// `MemoRepository` とは分けています。まとめ書きをしない実装にまで
/// 監視の責務を負わせると、「通知を出さない実装」が既定になり、
/// **配線漏れが静かに隠れる**ためです。実装するのはまとめ書きをする側だけです。
///
/// - Important: 購読者は 1 つだけを想定しています（`AppRootViewModel`）。
///   `AsyncStream` は複数購読者へ配れません。
nonisolated protocol MemoWriteMonitoring: Sendable {
    var writeStates: AsyncStream<MemoWriteState> { get }
}
