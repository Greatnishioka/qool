import AppKit
import SwiftUI

/// 輪郭の内側でだけクリックを受ける `NSHostingView`。
///
/// **この機能の肝です。** 輪郭の外へ来たクリックは `nil` を返して素通しし、背面のアプリへ届きます。
/// 透明にしただけの四角いウィンドウでは、見えない角が背面のクリックを奪います。
final class ContourHostingView<Content: View>: NSHostingView<Content> {
    /// 正規化（`0...1`、左上原点）した輪郭。ビューの大きさが変わっても持ち直す必要はありません。
    var contours: [CanvasPathContour]

    private let contourHitTest = ContourHitTest()

    init(rootView: Content, contours: [CanvasPathContour]) {
        self.contours = contours
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(rootView: Content) {
        self.contours = []
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard contains(convert(point, from: superview)) else {
            return nil
        }

        return super.hitTest(point)
    }

    private func contains(_ point: CGPoint) -> Bool {
        contourHitTest.contains(point, in: contours, bounds: bounds, isTopLeftOrigin: isFlipped)
    }
}
