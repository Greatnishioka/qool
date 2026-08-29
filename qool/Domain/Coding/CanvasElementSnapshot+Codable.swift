/// 合成 `Codable` を使わない理由: 人が読める JSON にする /
/// 欠けたキーを既定値で埋める / 復号時にも不変条件を通す。
nonisolated extension CanvasElementSnapshot {
    /// `CanvasElement` から `unionSourceElements` を除いたものなので、同じ表現を使い回します。
    /// 結合はネストしない（構成元は 1 段のまま）ため、この往復で情報は落ちません。
    init(from decoder: any Decoder) throws {
        self.init(element: try CanvasElement(from: decoder))
    }

    func encode(to encoder: any Encoder) throws {
        try element.encode(to: encoder)
    }
}
