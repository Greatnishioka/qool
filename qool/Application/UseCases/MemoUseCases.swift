import Foundation

/// 保留している書き込みを確定する。
///
/// アプリ終了時とパネルを閉じるときに実行しないと、
/// [まとめ書き](../../Infrastructure/Persistence/DebouncedMemoRepository.swift)の分が失われます。
nonisolated struct FlushMemosUseCase {
    var repository: MemoRepository

    func execute() async throws {
        try await repository.flush()
    }
}

/// 書き込み状態を購読する。
///
/// まとめ書きをしないリポジトリでは監視対象がないため、`nil` を受け取ります。
nonisolated struct ObserveWriteStatesUseCase {
    var monitor: (any MemoWriteMonitoring)?

    func execute() -> AsyncStream<MemoWriteState> {
        monitor?.writeStates ?? AsyncStream { $0.finish() }
    }
}

nonisolated struct LoadMemosUseCase {
    var repository: MemoRepository

    func execute() throws -> [Memo] {
        try repository.loadMemos()
    }
}

nonisolated struct CreateMemoUseCase {
    var repository: MemoRepository

    func execute() async throws -> Memo {
        let memo = Memo(title: "新規メモ")
        try await repository.save(memo)

        return memo
    }
}

nonisolated struct SaveMemoUseCase {
    var repository: MemoRepository

    /// 保存した内容を返す。
    ///
    /// `updatedAt` をここで更新するため、**呼び出し元が持っているメモは保存直後に古くなります。**
    /// 一覧は更新日時の降順で並ぶので、戻り値で置き換えないと並び順が壊れます。
    @discardableResult
    func execute(_ memo: Memo) async throws -> Memo {
        var updatedMemo = memo
        updatedMemo.updatedAt = Date()
        try await repository.save(updatedMemo)

        return updatedMemo
    }
}
