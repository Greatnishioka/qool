import CoreGraphics

nonisolated extension CGRect {
    /// 正規化座標（`0...1`）の外へはみ出した分を切り詰める。
    ///
    /// 幅・高さは `0.01` を下回りません。潰れた矩形から輪郭を作ると
    /// 点が 1 箇所に重なり、以降の平滑化が 0 除算に落ちるためです。
    func clampedToUnit() -> CGRect {
        let minX = max(0, self.minX)
        let minY = max(0, self.minY)
        let maxX = min(1, self.maxX)
        let maxY = min(1, self.maxY)

        return CGRect(
            x: minX,
            y: minY,
            width: max(0.01, maxX - minX),
            height: max(0.01, maxY - minY)
        )
    }
}
