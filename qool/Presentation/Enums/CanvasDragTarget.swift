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
    /// 角を掴んだ変形。**掴んだ角は途中で変えません。**
    ///
    /// 縦横比を保つかは途中で変わり得る（⇧ の押し直し）ので、ここに持ちます。
    /// 見た目と確定結果が食い違わないよう、確定にも同じ値を使います。
    case resizing(
        elementID: CanvasElement.ID,
        corner: CanvasResizeCorner,
        current: CGPoint,
        preservesAspectRatio: Bool
    )
}
