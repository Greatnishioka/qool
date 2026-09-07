import CoreGraphics

/// フローティングメモの外形。ウィンドウの大きさとヒットテストの両方に使います。
nonisolated struct FloatingMemoOutline: Equatable {
    /// キャンバス座標での外接矩形。ウィンドウの縦横比はここから決まります。
    let bounds: CGRect
    /// `bounds` を単位空間として正規化した輪郭。穴あき形状もあるため複数持ちます。
    ///
    /// **余白とぼかしで広がった分を含みます。** ウィンドウの大きさとクリック判定はこちらです。
    let contours: [CanvasPathContour]

    /// 紙の色を敷く形。`contours` から余白とぼかしを除いたものです。
    ///
    /// **ここに `contours` を使うと、ぼかした縁まで紙で塗り潰されて硬い縁になります。**
    /// ぼけた部分は画像自身のアルファに任せます。
    let paperContours: [CanvasPathContour]
}
