import Foundation

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
/// ## flush を忘れるとデータが消えます
///
/// 保留中にプロセスが終わると、その分は失われます。
/// 呼び出し側はアプリ終了時とパネルを閉じるときに `flush()` を呼んでください。
final class DebouncedMemoRepository: MemoRepository {
    private let base: MemoRepository
    private let interval: Duration
    private var pendingMemos: [Memo.ID: Memo] = [:]
    private var writeTask: Task<Void, Never>?

    /// - Parameters:
    ///   - base: 実際に書き込むリポジトリ。
    ///   - interval: 最後の保存からこの時間が経つと書き込みます。
    init(wrapping base: MemoRepository, interval: Duration = .milliseconds(500)) {
        self.base = base
        self.interval = interval
    }

    deinit {
        writeTask?.cancel()
    }

    // MARK: - MemoRepository

    /// 包んだリポジトリの内容に、保留中の内容を重ねて返す。
    func loadMemos() -> [Memo] {
        var memos = base.loadMemos()

        for pendingMemo in pendingMemos.values {
            if let index = memos.firstIndex(where: { $0.id == pendingMemo.id }) {
                memos[index] = pendingMemo
            } else {
                memos.append(pendingMemo)
            }
        }

        return memos.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ memo: Memo) {
        // 同じメモへの連続保存は、最後のものだけ残れば足ります。
        pendingMemos[memo.id] = memo
        scheduleWrite()
    }

    func delete(id: Memo.ID) {
        // 保留中の書き込みを取り消してから消す。
        // 先に base へ渡すと、直後の flush で復活してしまいます。
        pendingMemos[id] = nil
        base.delete(id: id)
    }

    func flush() {
        writeTask?.cancel()
        writeTask = nil

        guard !pendingMemos.isEmpty else {
            return
        }

        let memosToWrite = pendingMemos
        pendingMemos = [:]

        for memo in memosToWrite.values {
            base.save(memo)
        }
    }

    // MARK: -

    private func scheduleWrite() {
        // 保存のたびに前の予約を捨てて取り直す。
        // 操作が続いている間は書かず、止まってから書くための形です。
        writeTask?.cancel()
        writeTask = Task { [weak self, interval] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                // キャンセルされた＝より新しい保存が来た。ここでは書かない。
                return
            }

            self?.flush()
        }
    }
}
