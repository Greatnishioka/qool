import AppKit

/// [SpaceKeyReader](SpaceKeyReader.swift) が載せるビュー。
final class SpaceKeyWatchingView: NSView {
    /// スペースの `keyCode`。
    private static let spaceKeyCode: UInt16 = 49

    var onChange: ((Bool) -> Void)?

    private var monitor: Any?
    private var isPressed = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        removeMonitor()

        guard window != nil else {
            // 押したまま閉じても、押しっぱなしの状態を残しません。
            setPressed(false)
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  event.keyCode == Self.spaceKeyCode else {
                return event
            }

            self.setPressed(event.type == .keyDown)

            return nil
        }
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else {
            return
        }

        isPressed = pressed
        onChange?(pressed)
    }

    private func removeMonitor() {
        guard let monitor else {
            return
        }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
