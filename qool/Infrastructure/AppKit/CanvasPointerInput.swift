import AppKit
import SwiftUI

/// スクロール 1 回分の入力。
nonisolated struct ScrollWheelInput {
    let deltaX: CGFloat
    let deltaY: CGFloat
    /// ビュー内の位置（左上原点）。拡大の中心に使います。
    let location: CGPoint
    /// トラックパッドなら `true`。**マウスホイールと役割を分けるための唯一の手掛かりです。**
    let isPrecise: Bool
    /// ⌘ が押されているか。押されていれば拡大縮小にします。
    let wantsZoom: Bool
    /// ⇧ が押されているか。ホイールの上下を左右移動として扱います。
    let wantsHorizontal: Bool
}

/// マウスホイール / トラックパッドの 2 本指スクロールを拾う。
///
/// **SwiftUI にホイールを受け取る手段がありません。** `ScrollView` の中でしか使えないため、
/// キャンバス操作に使うには AppKit を挟む必要があります。
///
/// **クリックは奪いません。** `hitTest` が常に `nil` を返すので、重ねて置いても
/// 下の SwiftUI のジェスチャがそのまま動きます。そのぶん通常の経路では
/// スクロールも届かなくなるため、イベントは監視で受け取ります。
struct ScrollWheelReader: NSViewRepresentable {
    let onScroll: (ScrollWheelInput) -> Void

    func makeNSView(context: Context) -> ScrollWheelCatchingView {
        let view = ScrollWheelCatchingView()
        view.onScroll = onScroll

        return view
    }

    func updateNSView(_ nsView: ScrollWheelCatchingView, context: Context) {
        nsView.onScroll = onScroll
    }
}

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

/// スペースキーが押されているかを見る。**手のひらツールの代わり**です。
///
/// **押下は握り潰します。** スペースは既定でフォーカス中のボタンを押すため、
/// そのまま流すと「適用」などが動いてしまいます。
struct SpaceKeyReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> SpaceKeyWatchingView {
        let view = SpaceKeyWatchingView()
        view.onChange = onChange

        return view
    }

    func updateNSView(_ nsView: SpaceKeyWatchingView, context: Context) {
        nsView.onChange = onChange
    }
}

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
