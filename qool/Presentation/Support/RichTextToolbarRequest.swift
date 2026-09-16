import CoreGraphics

/// 書式の道具を出してほしい、という要求。
///
/// **押されたときの行き先を一緒に持ちます。** 道具はキャンバスにも
/// デスクトップに貼ったメモにも出るので、当てる先は出した側しか知りません
/// （[#21](https://github.com/Greatnishioka/qool/issues/21) の段階 5）。
///
/// **閉包を `@Published` に載せるため、渡す側は必ず弱参照で捕まえます。**
/// 強く持つと、キャンバスを閉じても ViewModel が解放されません。
struct RichTextToolbarRequest {
    /// 選んだ範囲の矩形。**画面座標です。**
    ///
    /// 道具は別のウィンドウに出ます。要素の中の座標で渡すと、
    /// 貼ったメモのように縮小された窓から来たときに意味が変わります。
    let selectionRect: CGRect
    let onStyle: (InlineMarkdownStyle) -> Void
    let onColor: (RGBAComponents?) -> Void
}
