/// 永続化の状態。画面に出す内容を決めるために使います。
enum MemoPersistenceStatus: Equatable {
    /// 保存できている。何も表示しません。
    case ok
    /// 保存に失敗し、自動で再試行している。
    case retrying
    /// 再試行しても失敗が続いている。
    case failing
}
