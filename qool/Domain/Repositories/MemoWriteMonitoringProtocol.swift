import Foundation

/// 書き込み状態を通知する。
///
/// `MemoRepositoryProtocol` とは分けています。まとめ書きをしない実装にまで
/// 監視の責務を負わせると、「通知を出さない実装」が既定になり、
/// **配線漏れが静かに隠れる**ためです。実装するのはまとめ書きをする側だけです。
///
/// - Important: 購読者は 1 つだけを想定しています（`AppRootViewModel`）。
///   `AsyncStream` は複数購読者へ配れません。
nonisolated protocol MemoWriteMonitoringProtocol: Sendable {
    var writeStates: AsyncStream<MemoWriteState> { get }
}
