import CoreGraphics
import SwiftUI

/// 本文を書き換えるための持ち回り。
///
/// **ばらばらに渡すのをやめました。** 渡す相手が増えるたびに呼び出し側が
/// 5 つの引数を組み立てることになり、どれが何のためか読めなくなります。
///
/// **渡さなければ表示だけ**になります。デスクトップに貼ったメモがその状態です
/// （[#21](https://github.com/Greatnishioka/qool/issues/21) の段階 5 で書き換えられるようにします）。
struct CanvasTextEditing {
    /// 書き換えられる状態か。**偽なら入力を受け取りません。**
    let isEditing: Bool
    /// 本文の選択。**両方向です。** 道具から書式を付けると、中身と一緒に選択も戻ってきます。
    let selection: Binding<NSRange>
    let onChange: (String) -> Void
    let onEndEditing: () -> Void
    /// 選択のある行の位置を要素の中の座標で返します。**道具を浮かせる場所**です。
    let onSelectionGeometry: (CGRect?) -> Void
}
