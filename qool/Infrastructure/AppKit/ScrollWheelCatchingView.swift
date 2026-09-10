import AppKit

/// [ScrollWheelReader](ScrollWheelReader.swift) が載せるビュー。
///
/// **監視でイベントを受け取ります。** `hitTest` が `nil` を返すぶん通常の経路では
/// スクロールも届かないため、`NSEvent` の監視を張って自分の範囲の分だけ拾います。
final class ScrollWheelCatchingView: NSView {
    var onScroll: ((ScrollWheelInput) -> Void)?

    private var monitor: Any?

    /// SwiftUI と原点を揃えます。上下が逆だと拡大の中心がずれます。
    override var isFlipped: Bool { true }

    /// クリックは下のビューへ通します。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        removeMonitor()

        guard window != nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window, event.window === window else {
                return event
            }

            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point) else {
                return event
            }

            self.onScroll?(
                ScrollWheelInput(
                    deltaX: event.scrollingDeltaX,
                    deltaY: event.scrollingDeltaY,
                    location: point,
                    isPrecise: event.hasPreciseScrollingDeltas,
                    wantsZoom: event.modifierFlags.contains(.command),
                    wantsHorizontal: event.modifierFlags.contains(.shift)
                )
            )

            // 使ったイベントは下へ流しません。
            return nil
        }
    }

    /// **解除はここだけで行います。** `deinit` は `MainActor` の外から呼ばれるため
    /// 監視を触れません。ビューが外れるときは必ず `window` が `nil` になって
    /// ここを通るので、監視が残ることはありません。
    private func removeMonitor() {
        guard let monitor else {
            return
        }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
