import AppKit
import SwiftUI

/// 書式の道具を載せた小さな窓を、選んだ範囲の上へ開け閉めする。
///
/// **アプリに 1 枚だけです。** キャンバスと貼ったメモで同時に出ると、
/// どちらの選択に効くのか分からなくなります。
///
/// [FloatingMemoWindowManager](FloatingMemoWindowManager.swift) と同じ役割分担です。
/// 出す・引っ込めるの判断は呼び出し側が持ち、ここはウィンドウだけを見ます。
@MainActor
final class RichTextToolbarPanelManager {
    /// 影が窓の縁で切れないように入れる余白。**窓の影は使いません。**
    /// 形が丸いので、四角い窓の影を付けると角が浮きます。
    private static let shadowInset: CGFloat = 8

    private let placement = RichTextToolbarPlacement()
    private var panel: RichTextToolbarPanel?

    /// 選んだ範囲の上へ浮かべる。
    ///
    /// - Parameter selectionRect: **画面座標**の選択範囲。窓をまたぐので、
    ///   どちらの窓から来ても同じ意味になる座標でしか置き場所を決められません。
    func show<Content: View>(_ content: Content, near selectionRect: CGRect) {
        let panel = panel ?? makePanel()
        self.panel = panel

        // **型を消して持ちます。** `padding` を付けた型は名前を書けないので、
        // 作り直さずに中身だけ差し替えるにはこれが要ります。
        let hostingView = hostingView(in: panel, showing: AnyView(content.padding(Self.shadowInset)))
        let size = hostingView.fittingSize
        let frame = NSRect(
            origin: placement.origin(
                for: selectionRect,
                panelSize: size,
                within: visibleFrame(containing: selectionRect)
            ),
            size: size
        )

        // **同じ場所なら動かしません。** `setFrame` は 1 回 6ms ほどかかります（実機で計測）。
        // スクロール中は毎フレーム通るので効きます。
        if panel.frame != frame {
            // **`display: false` です。** `true` はその場で描き直しを強制するので、
            // AppKit のまとめ描きが効きません。
            panel.setFrame(frame, display: false)
        }

        guard !panel.isVisible else {
            return
        }

        // **`orderFrontRegardless` です。** `makeKeyAndOrderFront` だと、
        // 出した瞬間に書いている場所から入力権が離れます。
        panel.orderFrontRegardless()
    }

    /// 道具を載せるビュー。**作り直さず、中身だけ差し替えます。**
    ///
    /// `contentView` に代入し直すと 1 回 4ms ほどかかります（実機で計測）。
    /// スクロール中は毎フレーム通るので、これだけで体感が変わります。
    /// [FloatingMemoWindowManager.update](FloatingMemoWindowManager.swift) と同じ考えです。
    private func hostingView(
        in panel: RichTextToolbarPanel,
        showing rootView: AnyView
    ) -> NSHostingView<AnyView> {
        if let existing = panel.contentView as? NSHostingView<AnyView> {
            existing.rootView = rootView

            return existing
        }

        let created = NSHostingView(rootView: rootView)
        panel.contentView = created

        return created
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: -

    private func makePanel() -> RichTextToolbarPanel {
        let panel = RichTextToolbarPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 1, height: 1)),
            // **`.nonactivatingPanel` が要ります。** 無いと、押したときにアプリが
            // 前面化する経路が走り、貼ったメモの窓からフォーカスが外れます。
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // **既定の `true` のままだと二重解放で落ちます。** こちらが強参照を持つためです。
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // 貼ったメモは `.floating` なので、それより上の階層へ出します。
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // アプリを離れたら引っ込めます。他のアプリの上に浮いたままだと、
        // 貼ったメモと違って何に効く道具なのか分かりません。
        panel.hidesOnDeactivate = true

        return panel
    }

    /// 選択のある画面の作業領域。**複数ディスプレイで、書いている側の画面へ出します。**
    ///
    /// 画面が 1 枚も取れないときは選択の矩形をそのまま返し、寄せずに出します。
    private func visibleFrame(containing rect: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main

        return screen?.visibleFrame ?? rect
    }
}
