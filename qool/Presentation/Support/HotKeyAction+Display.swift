/// 表示文字列は Presentation に置きます。Domain は文言を持ちません。
nonisolated extension HotKeyAction {
    var displayName: String {
        switch self {
        case .toggleMainMemo:
            return "メインのメモを出す / 隠す"
        case .createMemo:
            return "新しいメモを作る"
        }
    }
}
