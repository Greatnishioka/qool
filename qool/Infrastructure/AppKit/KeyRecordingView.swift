import AppKit

/// 押されたキーを 1 回だけ受け取るビュー。ホットキーの設定に使います。
///
/// **`NSEvent` のローカルモニタではなくビューにしているのは、**記録中だけキーを奪いたいからです。
/// モニタだと、記録していない間の入力まで通り抜けを気にする必要が出ます。
final class KeyRecordingView: NSView {
    var onRecord: ((UInt16, HotKeyModifiers) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    func beginRecording() {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode != VirtualKey.escape.rawValue else {
            onCancel?()

            return
        }

        onRecord?(event.keyCode, HotKeyModifiers(event.modifierFlags))
    }

    /// **⌘ を含む組み合わせは `keyDown` より先にここへ来ます。** 受けないと ⌘ 付きが記録できません。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return false
        }

        keyDown(with: event)

        return true
    }

    override func resignFirstResponder() -> Bool {
        onCancel?()

        return super.resignFirstResponder()
    }
}
