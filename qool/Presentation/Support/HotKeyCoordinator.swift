import AppKit
import Combine
import SwiftUI

/// プレフィックスを受けて 2 打目を待ち、割り当てられた操作を実行する。
///
/// **`⇧⌃Q` と `F` の同時押しは登録できません。** グローバルホットキーの登録 API が受け取れるのは
/// 「修飾キー + 通常キー 1 つ」だけで、`Q` も `F` も通常キーだからです。
/// そのため 2 ストローク（押して離す → 次を押す）になります。
@MainActor
final class HotKeyCoordinator: ObservableObject {
    private nonisolated static let overlayVerticalOffsetRatio = 0.18

    /// 登録できなかったときの理由。ほかのアプリが同じキーを取っている場合に出ます。
    @Published private(set) var registrationFailureMessage: String?
    @Published private(set) var mainMemoID: Memo.ID?
    @Published private(set) var configuration: HotKeyConfiguration

    private let viewModel: AppRootViewModel
    private let floatingMemos: FloatingMemoPresenter
    private let settings: any AppSettingsProtocol
    private let globalHotKey: any GlobalHotKeyProtocol

    private var overlayPanel: HotKeyOverlayPanel?

    init(
        viewModel: AppRootViewModel,
        floatingMemos: FloatingMemoPresenter,
        settings: any AppSettingsProtocol,
        globalHotKey: any GlobalHotKeyProtocol
    ) {
        self.viewModel = viewModel
        self.floatingMemos = floatingMemos
        self.settings = settings
        self.globalHotKey = globalHotKey
        mainMemoID = settings.mainMemoID
        configuration = settings.hotKeyConfiguration
    }

    func start() {
        register(configuration.prefix)
    }

    @discardableResult
    private func register(_ prefix: HotKeyShortcut) -> Bool {
        do {
            try globalHotKey.register(prefix) { [weak self] in
                self?.prefixPressed()
            }
            registrationFailureMessage = nil

            return true
        } catch {
            registrationFailureMessage = error.localizedDescription

            return false
        }
    }

    // MARK: - 設定の変更

    func updatePrefix(keyCode: UInt16, modifiers: HotKeyModifiers) {
        var updated = configuration
        updated.prefix = HotKeyShortcut(keyCode: keyCode, modifiers: modifiers)
        apply(updated)
    }

    func updateBinding(keyCode: UInt16, for action: HotKeyAction) {
        var updated = configuration
        updated.bindings.removeAll { $0.action == action }
        updated.bindings.append(HotKeyBinding(keyCode: keyCode, action: action))
        // 並びが押すたびに変わるとヒント一覧が読みにくいので、操作の定義順へ戻します。
        updated.bindings.sort { lhs, rhs in
            let order = HotKeyAction.allCases

            return (order.firstIndex(of: lhs.action) ?? 0) < (order.firstIndex(of: rhs.action) ?? 0)
        }
        apply(updated)
    }

    func resetConfiguration() {
        apply(.default)
    }

    /// **修飾キーなしのプレフィックスは受け付けません。** OS 全体で素のキーを奪うと、
    /// ほかのアプリでその文字が打てなくなります。
    func prefixRejection(keyCode: UInt16, modifiers: HotKeyModifiers) -> String? {
        guard !modifiers.isEmpty else {
            return "⌘ ⌃ ⌥ ⇧ のいずれかと組み合わせてください"
        }

        return nil
    }

    func bindingRejection(keyCode: UInt16, for action: HotKeyAction) -> String? {
        if keyCode == VirtualKey.escape.rawValue {
            return "esc は取り消しに使うため割り当てられません"
        }

        if let conflict = configuration.bindings.first(where: { $0.keyCode == keyCode && $0.action != action }) {
            return "\(conflict.action.displayName)と重なっています"
        }

        return nil
    }

    func keyCode(for action: HotKeyAction) -> UInt16? {
        configuration.bindings.first { $0.action == action }?.keyCode
    }

    /// **登録できたときだけ設定を書き換えます。**
    /// 先に保存すると、ほかのアプリと衝突するキーを選んだだけで、
    /// 動いていた割り当てまで失い、再起動しても失敗する設定が読み込まれます。
    private func apply(_ updated: HotKeyConfiguration) {
        if updated.prefix != configuration.prefix {
            guard register(updated.prefix) else {
                // 登録は前のキーを解除してから行うため、失敗したら戻しておきます。
                let failureMessage = registrationFailureMessage
                register(configuration.prefix)
                registrationFailureMessage = failureMessage

                return
            }
        }

        settings.hotKeyConfiguration = updated
        configuration = updated
    }

    func isMain(_ memo: Memo) -> Bool {
        mainMemoID == memo.id
    }

    func setMain(_ memo: Memo) {
        settings.mainMemoID = memo.id
        mainMemoID = memo.id
    }

    // MARK: - 2 ストローク

    /// 出ている最中にもう一度押されたら、何もせず閉じます。取り消しの手段になります。
    private func prefixPressed() {
        guard overlayPanel == nil else {
            dismissOverlay()

            return
        }

        showOverlay()
    }

    private func secondStrokePressed(keyCode: UInt16) {
        dismissOverlay()

        guard keyCode != VirtualKey.escape.rawValue,
              let action = configuration.action(forKeyCode: keyCode) else {
            return
        }

        perform(action)
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .toggleMainMemo:
            toggleMainMemo()
        case .createMemo:
            Task {
                guard let memo = await viewModel.createMemo() else {
                    return
                }

                viewModel.requestCanvas(for: memo.id)
            }
        }
    }

    /// 指定がなければ**直近に更新したメモ**を出します。
    /// 一度も選んでいない状態で押されたときに、何も起きないのを避けるためです。
    private func toggleMainMemo() {
        guard let memo = viewModel.memos.first(where: { $0.id == mainMemoID }) ?? viewModel.memos.first else {
            return
        }

        if memo.floatingOrigin == nil {
            floatingMemos.pin(memo)
        } else {
            floatingMemos.unpin(memo.id)
        }
    }

    // MARK: - オーバーレイ

    private func showOverlay() {
        let hostingView = NSHostingView(
            rootView: HotKeyOverlayView(prefix: configuration.prefix, bindings: configuration.bindings)
        )
        // 明示的に透明にします。既定のままだと、パネルの四角形が背景として残ることがあります。
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let size = hostingView.fittingSize
        let panel = HotKeyOverlayPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // ヒント一覧はキーを取らないので、パネル自身が `keyDown` を受け取ります。
        panel.initialFirstResponder = nil
        panel.onKeyDown = { [weak self] keyCode in
            self?.secondStrokePressed(keyCode: keyCode)
        }
        panel.onResignKey = { [weak self] in
            self?.dismissOverlay()
        }
        panel.setFrame(NSRect(origin: Self.overlayOrigin(for: size), size: size), display: true)
        panel.makeKeyAndOrderFront(nil)

        overlayPanel = panel
    }

    /// **先にコールバックを外します。** `close()` は `resignKey` を呼ぶため、
    /// 付けたままだとここへ戻ってきます。
    private func dismissOverlay() {
        guard let panel = overlayPanel else {
            return
        }

        overlayPanel = nil
        panel.onKeyDown = nil
        panel.onResignKey = nil
        panel.close()
    }

    /// 画面の中央より少し上。**視線の位置に出す**ためで、Spotlight などと同じ考え方です。
    private nonisolated static func overlayOrigin(for size: NSSize) -> NSPoint {
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero

        return NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2 + visibleFrame.height * overlayVerticalOffsetRatio
        )
    }
}
