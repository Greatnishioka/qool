/// プレフィックスに続けて押したキーで起こす操作。
nonisolated enum HotKeyAction: String, CaseIterable, Codable, Sendable {
    /// メインのメモをデスクトップに貼る／はがす。
    case toggleMainMemo
    case createMemo
}
