import Foundation

/// 書き込み状態を通知する。実装するのはまとめ書きをする側だけです。
/// `MemoRepositoryProtocol` に混ぜると「通知を出さない実装」が既定になり、配線漏れが静かに隠れます。
///
/// - Important: 購読者は 1 つだけ。`AsyncStream` は複数購読者へ配れません。
nonisolated protocol MemoWriteMonitoringProtocol: Sendable {
    var writeStates: AsyncStream<MemoWriteState> { get }
}
