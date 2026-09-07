/// ホットキーの修飾キー。
///
/// **`NSEvent.ModifierFlags` や Carbon の定数を持ち込みません。**
/// 生値は qool が決めたもので、OS の値への変換は Infrastructure の責務です。
/// 実装方式を差し替えても、この値のまま保存されたものが読み続けられます。
nonisolated struct HotKeyModifiers: OptionSet, Hashable, Codable, Sendable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let shift = HotKeyModifiers(rawValue: 1 << 0)
    static let control = HotKeyModifiers(rawValue: 1 << 1)
    static let option = HotKeyModifiers(rawValue: 1 << 2)
    static let command = HotKeyModifiers(rawValue: 1 << 3)
}
