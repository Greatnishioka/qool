import CoreGraphics

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
