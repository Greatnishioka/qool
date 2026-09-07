/// 2 打目のキーと操作の対応。
nonisolated struct HotKeyBinding: Equatable, Hashable, Codable, Sendable {
    var keyCode: UInt16
    var action: HotKeyAction

    init(keyCode: UInt16, action: HotKeyAction) {
        self.keyCode = keyCode
        self.action = action
    }

    init(_ key: VirtualKey, _ action: HotKeyAction) {
        self.init(keyCode: key.rawValue, action: action)
    }
}
