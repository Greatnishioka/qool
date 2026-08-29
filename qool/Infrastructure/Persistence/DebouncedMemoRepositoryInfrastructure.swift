import Foundation
import Synchronization

/// 書き込みをまとめ、直列化して、包んだリポジトリへ渡すデコレータ。
///
/// ## 3 つの役割
///
/// 1. **まとめる。** スライダーのような連続操作で数十回走る保存を、1 回の書き込みにする
/// 2. **直列にする。** 書き込みが並走すると、古い内容が新しい内容を上書きしうる
/// 3. **再試行する。** 失敗しても未保存の内容を保持し、有限回リトライする
///
/// ## ジョブの列ではなく「あるべき状態」を持ちます
///
/// 保存要求をジョブとして積むと、**失敗したジョブの再投入が順序を壊します。**
///
/// ```text
/// save(A) 失敗 → delete(A) 成功 → save(A) を再投入して成功 → A が復活する
/// ```
///
/// そのため `[Memo.ID: PendingMutation]` として **ID ごとに最新の意図だけ**を持ちます。
/// 後から来た削除は保存を上書きするので、復活は起こりません。
///
/// ## 直列化はタスクの鎖で行います
///
/// `enqueueDrain()` が「前の書き込みの完了を待ってから実行する」タスクを作り、
/// 末尾を繋ぎ替えます。常駐 worker を置かずに順序を保証できます。
///
/// ## 失敗しても内容は捨てません
///
/// リトライ上限に達しても保留は残したままにし、`.failed` を通知します。
/// `flush()`（画面の「再試行」）から再開できます。
nonisolated final class DebouncedMemoRepositoryInfrastructure: MemoRepositoryProtocol, MemoWriteMonitoringProtocol {
    /// 1 件のメモに対する「あるべき状態」。
    private enum Mutation: Sendable {
        case upsert(Memo)
        case delete
    }

    private struct PendingMutation: Sendable {
        var mutation: Mutation
        /// 単調増加。書き込み完了時に「その間に新しい変更が来ていないか」を判定します。
        var revision: UInt64
        /// **この revision に対する**試行回数。
        ///
        /// drain のローカル変数に持たせると、drain が複数積まれたときに
        /// 同じ内容が上限を超えて書き込まれます。新しい変更が来れば 0 に戻ります。
        var attempts: Int = 0
    }

    /// 1 回の書き込みが失敗したあと、次にどうするか。
    private enum FailureOutcome {
        /// 新しい変更が来ていた。待たずに取り直す。
        case superseded
        /// まだ試せる。
        case retry(attempt: Int)
        /// 上限に達した。
        case exhausted
    }

    private struct State {
        var pending: [Memo.ID: PendingMutation] = [:]
        /// ディスクへ反映済みの revision。`flush()` の完了判定に使います。
        var persistedRevisions: [Memo.ID: UInt64] = [:]
        var nextRevision: UInt64 = 1
        var debounceTask: Task<Void, Never>?
        /// タスクの鎖の末尾。次の書き込みはこれの完了を待ちます。
        var writeTail: Task<Void, Never>?
    }

    /// 再試行の上限。到達しても内容は保持し、手動再試行で再開できます。
    private static let maximumAttempts = 3
    /// 500ms → 1s → 2s。ローカルの単一書き込みなので jitter は不要です。
    private static func backoff(afterAttempt attempt: Int) -> Duration {
        .milliseconds(500 * (1 << (attempt - 1)))
    }

    private let base: any MemoRepositoryProtocol
    private let interval: Duration
    private let state = Mutex(State())

    let writeStates: AsyncStream<MemoWriteState>
    private let stateContinuation: AsyncStream<MemoWriteState>.Continuation

    init(wrapping base: any MemoRepositoryProtocol, interval: Duration = .milliseconds(500)) {
        self.base = base
        self.interval = interval

        // 状態の通知なので、取りこぼしよりも「最新だけ届く」ほうが正しい形です。
        let (stream, continuation) = AsyncStream.makeStream(
            of: MemoWriteState.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        writeStates = stream
        stateContinuation = continuation
    }

    deinit {
        state.withLock { state in
            state.debounceTask?.cancel()
            state.writeTail?.cancel()
        }
        stateContinuation.finish()
    }

    // MARK: - MemoRepositoryProtocol

    /// 包んだリポジトリの内容に、未書き込みの意図を重ねて返す。
    ///
    /// 書いていないから見えない、という状態を外から観測させないためです。
    func loadMemos() throws -> [Memo] {
        var memos = try base.loadMemos()
        let pending = state.withLock { $0.pending }

        for (id, entry) in pending {
            switch entry.mutation {
            case let .upsert(memo):
                if let index = memos.firstIndex(where: { $0.id == id }) {
                    memos[index] = memo
                } else {
                    memos.append(memo)
                }
            case .delete:
                memos.removeAll { $0.id == id }
            }
        }

        return memos.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 意図を記録するだけなので失敗しません。書き込みの失敗は
    /// `writeStates` と `flush()` が伝えます。
    func save(_ memo: Memo) async throws {
        record(.upsert(memo), for: memo.id)
        scheduleDebouncedWrite()
    }

    /// 削除はまとめません。取り消しの意図は早く確定させたいためです。
    func delete(id: Memo.ID) async throws {
        record(.delete, for: id)
        await enqueueDrain().value
    }

    /// 呼び出し時点で未反映の変更が、すべてディスクへ反映されるまで待つ。
    /// より新しい内容で置き換えられて反映された場合も、満たされたものとして扱います。
    /// 有限回の再試行を終えても未反映なら投げます。
    func flush() async throws {
        let targets = state.withLock { state -> [Memo.ID: UInt64] in
            state.debounceTask?.cancel()
            state.debounceTask = nil

            // 明示的な `flush` は「もう一度試してほしい」という意思表示なので、
            // 自動リトライの上限をやり直します。
            // これがないと、一度諦めた内容は新しい編集が来るまで永久に書かれません。
            for id in state.pending.keys {
                state.pending[id]?.attempts = 0
            }

            return state.pending.mapValues(\.revision)
        }

        await enqueueDrain().value

        let unmet = state.withLock { state in
            targets.filter { id, revision in
                (state.persistedRevisions[id] ?? 0) < revision
            }
        }

        guard unmet.isEmpty else {
            throw MemoWriteFailure.notPersisted(count: unmet.count)
        }
    }

    // MARK: - 意図の記録

    private func record(_ mutation: Mutation, for id: Memo.ID) {
        state.withLock { state in
            let revision = state.nextRevision
            state.nextRevision += 1
            // 同じ ID への新しい意図は、古い意図を置き換えます。
            state.pending[id] = PendingMutation(mutation: mutation, revision: revision)
        }
    }

    // MARK: - まとめ書き

    private func scheduleDebouncedWrite() {
        state.withLock { state in
            state.debounceTask?.cancel()
            state.debounceTask = Task { [weak self, interval] in
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return  // より新しい保存が来た
                }

                await self?.enqueueDrain().value
            }
        }
    }

    // MARK: - 直列化

    /// 前の書き込みの完了を待ってから実行するタスクを作り、鎖の末尾に繋ぐ。
    private func enqueueDrain() -> Task<Void, Never> {
        state.withLock { state in
            let previous = state.writeTail
            let task = Task { [weak self] in
                await previous?.value
                await self?.drain()
            }
            state.writeTail = task

            return task
        }
    }

    /// 保留がなくなるまで 1 件ずつ書く。
    ///
    /// **1 件が失敗しても他のメモの処理は続けます。** 途中で抜けると、
    /// 書けないメモが 1 件あるだけで他のメモが永久に保存されなくなります
    /// （`FileMemoRepositoryInfrastructure` は 1 メモ = 1 ディレクトリなので、ID 単位の失敗は現実に起こります）。
    private func drain() async {
        var blocked: Set<Memo.ID> = []

        while let id = nextPendingID(excluding: blocked) {
            if await write(id: id) == false {
                // このメモは諦めて次へ。保留は残したままです。
                blocked.insert(id)
            }
        }

        notifyCompletion(hasBlocked: !blocked.isEmpty)
    }

    private func nextPendingID(excluding blocked: Set<Memo.ID>) -> Memo.ID? {
        state.withLock { state in
            state.pending.keys.first { !blocked.contains($0) }
        }
    }

    /// 空の判定と通知を**同じロックの中**で行います。
    /// 分けると、空を確認した直後に来た保存を取りこぼして `.idle` を流してしまいます。
    private func notifyCompletion(hasBlocked: Bool) {
        state.withLock { state in
            if hasBlocked {
                stateContinuation.yield(.failed)
            } else if state.pending.isEmpty {
                stateContinuation.yield(.idle)
            }
        }
    }

    /// 1 件の書き込み。失敗したら**その場で**再試行します。
    ///
    /// 末尾へ積み直すと後続を追い越し、順序が壊れます。
    /// - Returns: 上限に達せず処理を終えたら `true`。
    private func write(id: Memo.ID) async -> Bool {
        while true {
            // 毎回読み直します。再試行の間に削除が来ていれば、そちらが優先されます。
            guard let entry = state.withLock({ $0.pending[id] }) else {
                return true
            }

            // 試行回数は state が持つため、drain が何本積まれても上限は共通です。
            guard entry.attempts < Self.maximumAttempts else {
                return false
            }

            do {
                switch entry.mutation {
                case let .upsert(memo):
                    try await base.save(memo)
                case .delete:
                    try await base.delete(id: id)
                }

                markPersisted(id: id, revision: entry.revision)

                return true
            } catch {
                switch recordFailure(id: id, revision: entry.revision) {
                case .superseded:
                    continue
                case let .retry(attempt):
                    stateContinuation.yield(.retrying(attempt: attempt))
                    try? await Task.sleep(for: Self.backoff(afterAttempt: attempt))
                case .exhausted:
                    return false
                }
            }
        }
    }

    private func recordFailure(id: Memo.ID, revision: UInt64) -> FailureOutcome {
        state.withLock { state in
            // 失敗している間に新しい変更が来ていたら、そちらの試行回数は触りません。
            guard state.pending[id]?.revision == revision else {
                return .superseded
            }

            state.pending[id]?.attempts += 1
            let attempts = state.pending[id]?.attempts ?? Self.maximumAttempts

            return attempts < Self.maximumAttempts ? .retry(attempt: attempts) : .exhausted
        }
    }

    private func markPersisted(id: Memo.ID, revision: UInt64) {
        state.withLock { state in
            // 書き込み中に新しい意図が来ていたら、保留は消しません。
            if state.pending[id]?.revision == revision {
                state.pending[id] = nil
            }

            state.persistedRevisions[id] = max(state.persistedRevisions[id] ?? 0, revision)
        }
    }
}
