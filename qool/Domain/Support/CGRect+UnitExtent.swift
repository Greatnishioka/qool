import CoreGraphics

nonisolated extension CGRect {
    /// 正規化空間の範囲として成立しているか。
    ///
    /// **非有限値と 0 以下の幅・高さを弾きます。** 面積のない範囲は、
    /// 位置の換算で 0 除算になるか、割った結果が発散します。
    ///
    /// **`width` / `height` ではなく `size` を見ます。** `CGRect.width` は
    /// 符号を無視して絶対値を返すため、負の幅を持つ矩形を見逃します。
    var isValidUnitExtent: Bool {
        origin.x.isFinite && origin.y.isFinite
            && size.width.isFinite && size.height.isFinite
            && size.width > 0 && size.height > 0
    }
}
