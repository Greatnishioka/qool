import CoreGraphics

/// フローティングメモの外形。ウィンドウの大きさとヒットテストの両方に使います。
nonisolated struct FloatingMemoOutline: Equatable {
    /// キャンバス座標での外接矩形。ウィンドウの縦横比はここから決まります。
    let bounds: CGRect
    /// `bounds` を単位空間として正規化した輪郭。穴あき形状もあるため複数持ちます。
    let contours: [CanvasPathContour]
}
