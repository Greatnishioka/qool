import CoreGraphics

/// 検証中のテキストビューの状態。**画面に出して目で見るためのものです。**
///
/// **段階 0 の検証用で、判断が付いたら消します**
/// （[#21](https://github.com/Greatnishioka/qool/issues/21)）。
struct RichTextProbeDiagnostics: Equatable {
    /// TextKit 2 で動いているか。**古い経路へ落ちていないことの確認**です。
    var usesTextKit2 = false
    var isKeyWindow = false
    var isFirstResponder = false
    /// 変換中か。ここが真の間は属性を貼り直せません。
    var hasMarkedText = false
    var selectedLocation = 0
    var selectedLength = 0

    /// 入力側へ矩形を返したことがあるか。**一度も変換していなければ比べる意味がありません。**
    var hasInputSample = false

    /// **変換候補の窓を置く場所として、入力側へ返した矩形（画面座標）。**
    ///
    /// 縮小したビューの中で日本語入力が壊れるとしたら、ここがずれます。
    var lastInputRect: CGRect = .zero

    /// `lastInputRect` を返した**その瞬間**のキャレットの位置（画面座標）。
    ///
    /// **同じ瞬間で取らないと比べられません。** 変換が終わってキャレットが動いたあとの値と
    /// 引き算すると、ずれていないのに数百 pt の差が出ます（実際に出しました）。
    var caretRect: CGRect = .zero

    /// `lastInputRect` と `caretRect` のずれ。**0 でなければ縮小に追随できていません。**
    var inputRectGap: CGFloat {
        max(abs(lastInputRect.minX - caretRect.minX), abs(lastInputRect.minY - caretRect.minY))
    }
}
