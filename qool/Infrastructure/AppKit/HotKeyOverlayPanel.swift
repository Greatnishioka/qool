import AppKit

/// プレフィックスの 2 打目を受け取る小さなパネル。
///
/// **`.nonactivatingPanel` にすると、アプリを前面に出さないままキーウィンドウになれます。**
/// CGEvent tap でキーを横取りする手もありますが、そちらはアクセシビリティ権限が要ります。
/// 権限を求めずに済むことが、この方式を選ぶ理由です。
final class HotKeyOverlayPanel: NSPanel {
    var onKeyDown: ((UInt16) -> Void)?

    override var canBecomeKey: Bool { true }

    /// **既定の実装を呼びません。** 未処理のキーはビープを鳴らすため、ここで握り潰します。
    override func keyDown(with event: NSEvent) {
        onKeyDown?(event.keyCode)
    }
}
