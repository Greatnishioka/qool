import AppKit

/// デスクトップに貼るための枠なしウィンドウ。
///
/// **`canBecomeKey` / `canBecomeMain` を返さないと、`.borderless` のウィンドウは
/// キーウィンドウになれず、コンテキストメニューもキー入力も受け取れません。**
final class FloatingMemoWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
