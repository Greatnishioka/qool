import Foundation
import Synchronization

/// 書き込みをまとめてから、包んだリポジトリへ渡すデコレータ。
///
/// キャンバスは編集のたびに保存します。スライダーやテキスト入力のように
/// **連続して値が変わる操作では、1 回の操作で数十回の保存が走ります。**
/// そのすべてをディスクへ書くのは無駄なので、一定時間内の保存をまとめます。
///
/// ```text
/// save save save save save ... （スライダーのドラッグ中）
///                            └ 静まってから 1 回だけ書く
/// ```
///
/// ## 未書き込みの内容も読めます
///
/// `loadMemos()` は保留中の内容を重ねて返します。書いていないから見えない、
/// という状態を外から観測できないようにするためです。
///
/// ## 失敗した書き込みは保留に戻ります
///
/// 書き込みに失敗した分は保留へ戻すため、**次の周期で自動的に再試行されます。**
/// 呼び出し元は失敗を受け取りつつ、編集を続けられます。
///
/// ## flush を忘れるとデータが消えます
///
/// 保留中にプロセスが終わると、その分は失われます。
/// 呼び出し側はアプリ終了時とパネルを閉じるときに `flush()` を呼んでください。
///
/// ## 隔離について
///
/// 可変状態を `Mutex` で守り、型自体は `nonisolated` です。
/// アクタに縛ると、包んだ側の書き込みを別の実行文脈へ逃がせなくなります。
nonisolated final class DebouncedMemoRepository: MemoRepository {
    /// 保留中のメモと、書き込み予約。まとめて 1 つのロックで守ります。
    private struct State {
        var pendingMemos: [Memo.ID: Memo] = [:]
        var writeTask: Task<Void, Never>?
    }

    private let base: any MemoRepository
    private let interval: Duration
    private let state = Mutex(State())

    /// - Parameters:
    ///   - base: 実際に書き込むリポジトリ。
    ///   - interval: 最後の保存からこの時間が経つと書き込みます。
    init(wrapping base: any MemoRepository, interval: Duration = .milliseconds(500)) {
        self.base = base
        self.interval = interval
    }

    deinit {
        state.withLock { $0.writeTask?.cancel() }
    }

    // MARK: - MemoRepository

    /// 包んだリポジトリの内容に、保留中の内容を重ねて返す。
    func loadMemos() throws -> [Memo] {
        var memos = try base.loadMemos()
        let pendingMemos = state.withLock { $0.pendingMemos }

        for pendingMemo in pendingMemos.values {
            if let index = memos.firstIndex(where: { $0.id == pendingMemo.id }) {
                memos[index] = pendingMemo
            } else {
                memos.append(pendingMemo)
            }
        }

        return memos.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 保留に積むだけなので失敗しません。実際の書き込みの失敗は `flush()` が投げます。
    func save(_ memo: Memo) async throws {
        // 同じメモへの連続保存は、最後のものだけ残れば足ります。
        state.withLock { $0.pendingMemos[memo.id] = memo }
        scheduleWrite()
    }

    func delete(id: Memo.ID) async throws {
        // 保留中の書き込みを取り消してから消す。
        // 先に base へ渡すと、直後の flush で復活してしまいます。
        state.withLock { $0.pendingMemos[id] = nil }
        try await base.delete(id: id)
    }

    func flush() async throws {
        let memosToWrite = state.withLock { state -> [Memo.ID: Memo] in
            state.writeTask?.cancel()
            state.writeTask = nil

            let pending = state.pendingMemos
            state.pendingMemos = [:]

            return pending
        }

        guard !memosToWrite.isEmpty else {
            return
        }

        var failedMemos: [Memo.ID: Memo] = [:]
        var firstError: (any Error)?

        for memo in memosToWrite.values {
            do {
                try await base.save(memo)
            } catch {
                failedMemos[memo.id] = memo
                firstError = firstError ?? error
            }
        }

        guard let firstError else {
            return
        }

        // 失敗した分を保留へ戻して再試行させます。
        // 書き込み中に来た新しい保存を消さないよう、既にあるものは上書きしません。
        state.withLock { state in
            for (id, memo) in failedMemos where state.pendingMemos[id] == nil {
                state.pendingMemos[id] = memo
            }
        }
        scheduleWrite()

        throw firstError
    }

    // MARK: -

    private func scheduleWrite() {
        // 保存のたびに前の予約を捨てて取り直す。
        // 操作が続いている間は書かず、止まってから書くための形です。
        state.withLock { state in
            state.writeTask?.cancel()
            state.writeTask = Task { [weak self, interval] in
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    // キャンセルされた＝より新しい保存が来た。ここでは書かない。
                    return
                }

                // 自動書き込みでの失敗は保留へ戻り、次の周期で再試行されます。
                // 呼び出し元へ伝える経路は `flush()` を明示的に呼んだときです。
                try? await self?.flush()
            }
        }
    }
}
