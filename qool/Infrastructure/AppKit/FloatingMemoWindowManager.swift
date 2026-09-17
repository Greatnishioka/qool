import AppKit
import SwiftUI

/// 机の上の付箋のウィンドウを開閉し、**付箋 1 件につき 1 枚**に保ちます。
///
/// **鍵は付箋の id です。** 同じ雛形から何枚でも出せるので、雛形では数えられません
/// （[#29](https://github.com/Greatnishioka/qool/issues/29)）。
@MainActor
final class FloatingMemoWindowManager: NSObject, NSWindowDelegate {
    /// ウィンドウの大きさの上下限。**キャンバス座標をそのまま使うと、大きく描いたメモが画面を覆います。**
    private nonisolated static let minimumWidth: CGFloat = 120
    private nonisolated static let maximumWidth: CGFloat = 360
    private nonisolated static let maximumHeight: CGFloat = 480

    /// 位置を持たないメモを開くときに、画面中央からずらす量。重ねて開いても隠れないようにします。
    private static let cascadeStep: CGFloat = 24
    private static let cascadeCount = 5

    private var windows: [StickyNote.ID: FloatingMemoWindow] = [:]
    private var moveHandlers: [StickyNote.ID: (CGPoint) -> Void] = [:]

    override init() {
        super.init()
    }

    var showingNoteIDs: Set<StickyNote.ID> {
        Set(windows.keys)
    }

    func isShowing(_ noteID: StickyNote.ID) -> Bool {
        windows[noteID] != nil
    }

    /// 新しく出す付箋を置く位置。**出す操作の側で位置を決めて保存するため**に公開しています。
    func nextOrigin(for outline: FloatingMemoOutline) -> CGPoint {
        cascadeOrigin(for: Self.windowSize(for: outline.bounds))
    }

    /// 出す、または出したままのウィンドウの中身を最新へ差し替える。
    ///
    /// - Parameter onMove: ドラッグで動いたあとの左下位置。保存する側が受け取ります。
    func show<Content: View>(
        noteID: StickyNote.ID,
        outline: FloatingMemoOutline,
        origin: CGPoint,
        content: Content,
        onMove: @escaping (CGPoint) -> Void
    ) {
        moveHandlers[noteID] = onMove
        let size = Self.windowSize(for: outline.bounds)

        if let window = windows[noteID] {
            update(window, with: content, contours: outline.contours, size: size)

            return
        }

        let window = makeWindow(size: size)
        window.contentView = ContourHostingView(rootView: content, contours: outline.contours)
        window.setFrame(
            NSRect(origin: origin, size: size),
            display: true
        )

        windows[noteID] = window
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
    }

    /// 本文を書き換えるために、アプリごと前面へ出す。
    ///
    /// **`LSUIElement` のアプリは、ウィンドウを押しても前面に出ません。**
    /// キーウィンドウにはなるのでキャレットは出ますが、**アプリが非アクティブのままだと
    /// 入力メソッドが文字を渡してきません。** 日本語の変換候補が画面の隅に出たまま、
    /// 確定しても本文に何も入らない状態になります（実機で踏みました）。
    func activate(_ noteID: StickyNote.ID) {
        guard let window = windows[noteID] else {
            return
        }

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ noteID: StickyNote.ID) {
        moveHandlers.removeValue(forKey: noteID)

        guard let window = windows.removeValue(forKey: noteID) else {
            return
        }

        // 先に外さないと、閉じる過程の通知で消したはずのメモを触りにいきます。
        window.delegate = nil
        window.close()
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? FloatingMemoWindow,
              let noteID = windows.first(where: { $0.value === window })?.key else {
            return
        }

        moveHandlers[noteID]?(window.frame.origin)
    }

    // MARK: -

    private func makeWindow(size: NSSize) -> FloatingMemoWindow {
        let window = FloatingMemoWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // **既定の `true` のままだと二重解放で落ちます。** `close()` で AppKit が解放する一方、
        // こちらは `windows` で強参照を持っているためです。所有はこのクラスに一本化します。
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        // 仮想デスクトップを切り替えても付いてくる。貼った付箋としての振る舞いです。
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true

        return window
    }

    /// 中身を差し替える。**位置は動かしません。** 編集のたびに置いた場所へ戻られると使えません。
    private func update<Content: View>(
        _ window: FloatingMemoWindow,
        with content: Content,
        contours: [CanvasPathContour],
        size: NSSize
    ) {
        if let hostingView = window.contentView as? ContourHostingView<Content> {
            hostingView.rootView = content
            hostingView.contours = contours
        } else {
            window.contentView = ContourHostingView(rootView: content, contours: contours)
        }

        window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true)
    }

    private func cascadeOrigin(for size: NSSize) -> NSPoint {
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        let offset = CGFloat(windows.count % Self.cascadeCount) * Self.cascadeStep

        return NSPoint(
            x: visibleFrame.midX - size.width / 2 + offset,
            y: visibleFrame.midY - size.height / 2 - offset
        )
    }

    /// 外接矩形を上下限に収める。**縦横比は必ず保ちます。**
    /// ここが崩れると、描いた形とクリックの通る範囲がずれます。
    nonisolated static func windowSize(for bounds: CGRect) -> NSSize {
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let reduction = min(1, maximumWidth / width, maximumHeight / height)
        // 小さすぎるメモは掴めないので広げます。ただし高さの上限は超えません。
        let enlargement = min(
            max(1, minimumWidth / (width * reduction)),
            maximumHeight / (height * reduction)
        )
        let scale = reduction * enlargement

        return NSSize(width: width * scale, height: height * scale)
    }
}
