import Carbon.HIToolbox

/// Carbon の `RegisterEventHotKey` でホットキーを登録する。
///
/// **古い C の API ですが、グローバルホットキーでは今も事実上の標準です。**
/// `NSEvent` のグローバルモニタは監視しかできず、押したキーが裏のアプリにも流れるうえ、
/// アクセシビリティ権限が要ります。こちらは権限なしでキーを奪えます。
@MainActor
final class CarbonGlobalHotKeyInfrastructure: GlobalHotKeyProtocol {
    /// 自分が登録したホットキーだと見分けるための印。`'qool'` の 4 文字コード。
    private nonisolated static let signature = OSType(0x716F_6F6C)
    private nonisolated static let hotKeyIdentifier: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onPress: (() -> Void)?

    init() {}

    func register(_ shortcut: HotKeyShortcut, onPress: @escaping () -> Void) throws {
        unregister()
        try installHandlerIfNeeded()

        var registeredRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(from: shortcut.modifiers),
            EventHotKeyID(signature: Self.signature, id: Self.hotKeyIdentifier),
            GetEventDispatcherTarget(),
            0,
            &registeredRef
        )

        guard status == noErr, let registeredRef else {
            throw HotKeyRegistrationFailure.rejectedBySystem(status: Int(status))
        }

        hotKeyRef = registeredRef
        self.onPress = onPress
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        hotKeyRef = nil
        onPress = nil
    }

    /// **ハンドラは付けっぱなしにします。** 登録し直すたびに外して付けると、
    /// その隙に届いたイベントを取りこぼします。
    private func installHandlerIfNeeded() throws {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandler: EventHandlerRef?
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedHandler
        )

        guard status == noErr else {
            throw HotKeyRegistrationFailure.handlerUnavailable(status: Int(status))
        }

        eventHandler = installedHandler
    }

    fileprivate func handlePress() {
        onPress?()
    }

    private nonisolated static func carbonModifiers(from modifiers: HotKeyModifiers) -> UInt32 {
        var flags: UInt32 = 0

        if modifiers.contains(.shift) {
            flags |= UInt32(shiftKey)
        }
        if modifiers.contains(.control) {
            flags |= UInt32(controlKey)
        }
        if modifiers.contains(.option) {
            flags |= UInt32(optionKey)
        }
        if modifiers.contains(.command) {
            flags |= UInt32(cmdKey)
        }

        return flags
    }
}

/// Carbon へ渡す C の関数。**値をキャプチャできない**ため、`self` は `userData` で受け取ります。
private nonisolated func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return OSStatus(eventNotHandledErr)
    }

    // ポインタのまま渡すとデータ競合とみなされるので、数値にしてから跨がせます。
    let pointerValue = UInt(bitPattern: userData)

    // ホットキーイベントはメインスレッドへ届きます。
    return MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: pointerValue) else {
            return OSStatus(eventNotHandledErr)
        }

        Unmanaged<CarbonGlobalHotKeyInfrastructure>.fromOpaque(pointer)
            .takeUnretainedValue()
            .handlePress()

        return noErr
    }
}
