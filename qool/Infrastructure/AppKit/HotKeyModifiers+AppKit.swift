import AppKit

nonisolated extension HotKeyModifiers {
    /// AppKit の修飾キーを qool の表現へ移す。**変換をここに閉じ込めるのが腐敗防止層の役目です。**
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: HotKeyModifiers = []

        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }

        self = modifiers
    }
}
