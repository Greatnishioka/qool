/// ホットキーの割り当て。プレフィックス 1 つと、2 打目の対応表を持ちます。
///
/// **OS 全体へ登録するのはプレフィックスだけです。** 操作ごとに別々の組み合わせを予約すると、
/// 機能を足すたびに他アプリとの衝突を探すことになります。
nonisolated struct HotKeyConfiguration: Equatable, Codable, Sendable {
    var prefix: HotKeyShortcut
    var bindings: [HotKeyBinding]

    init(prefix: HotKeyShortcut, bindings: [HotKeyBinding]) {
        self.prefix = prefix
        self.bindings = bindings
    }

    static let `default` = HotKeyConfiguration(
        prefix: HotKeyShortcut(.q, modifiers: [.shift, .control]),
        bindings: [
            HotKeyBinding(.f, .toggleMainMemo),
            HotKeyBinding(.n, .createMemo)
        ]
    )

    func action(forKeyCode keyCode: UInt16) -> HotKeyAction? {
        bindings.first { $0.keyCode == keyCode }?.action
    }
}
