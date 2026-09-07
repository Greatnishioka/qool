nonisolated struct HotKeyShortcut: Equatable, Hashable, Codable, Sendable {
    var keyCode: UInt16
    var modifiers: HotKeyModifiers

    init(keyCode: UInt16, modifiers: HotKeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(_ key: VirtualKey, modifiers: HotKeyModifiers) {
        self.init(keyCode: key.rawValue, modifiers: modifiers)
    }
}
