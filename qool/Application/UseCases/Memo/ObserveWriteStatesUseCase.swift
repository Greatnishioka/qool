/// 書き込み状態を購読する。まとめ書きをしないリポジトリでは監視対象がないため、`nil` を受け取ります。
nonisolated struct ObserveWriteStatesUseCase {
    let monitor: (any MemoWriteMonitoringProtocol)?

    func callAsFunction() -> AsyncStream<MemoWriteState> {
        monitor?.writeStates ?? AsyncStream { $0.finish() }
    }
}
