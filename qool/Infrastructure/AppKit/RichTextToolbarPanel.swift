import AppKit

/// 書式の道具を載せる、キー入力を奪わない窓。
///
/// **`canBecomeKey` を返してはいけません。** 返すと、道具を押した瞬間に
/// テキストビューが first responder を失います。選んだ範囲が消えたまま書式が当たり、
/// 何も選んでいないときの振る舞い（記号だけ入る）になります。
final class RichTextToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
