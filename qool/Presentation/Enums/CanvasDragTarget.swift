import CoreGraphics

/// ドラッグが何を対象にしているか。
///
/// **同時に成立しない状態を型で排他にします。** Optional を並べて持つと
/// 「要素移動中かつ範囲選択中」のような、あり得ない組み合わせが作れてしまいます。
enum CanvasDragTarget {
    case none
    /// 選択済み要素の移動。
    case elements(Set<CanvasElement.ID>)
    /// Shift クリックの候補。動かさずに離したときだけ選択を反転します。
    case toggling(CanvasElement.ID)
    /// 結合の構成元の移動。
    case unionSource(CanvasElementSnapshot.ID)
    /// 範囲選択。
    case marquee(start: CGPoint, current: CGPoint)
}
