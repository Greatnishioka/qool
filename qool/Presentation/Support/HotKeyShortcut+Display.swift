nonisolated extension HotKeyShortcut {
    /// `⇧⌃Q` のような表記。**修飾キーの並びは macOS の慣習（⌃⌥⇧⌘）に合わせます。**
    var displayName: String {
        var symbols = ""

        if modifiers.contains(.control) {
            symbols += "⌃"
        }
        if modifiers.contains(.option) {
            symbols += "⌥"
        }
        if modifiers.contains(.shift) {
            symbols += "⇧"
        }
        if modifiers.contains(.command) {
            symbols += "⌘"
        }

        return symbols + VirtualKey.symbol(forKeyCode: keyCode)
    }
}
