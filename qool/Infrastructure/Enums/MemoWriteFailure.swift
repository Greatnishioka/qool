/// まとめ書きの結果、ディスクへ反映できなかった変更が残っていることを表します。
nonisolated enum MemoWriteFailure: Error {
    case notPersisted(count: Int)
}
