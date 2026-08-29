/// 合成 `Codable` を使わない理由: 人が読める JSON にする /
/// 欠けたキーを既定値で埋める / 復号時にも不変条件を通す。
nonisolated extension CanvasElementSnapshot {
    /// スナップショットは `CanvasElement` から `unionSourceElements` を除いたものなので、
    /// 同じ表現を使い回します。定義を二重に持たないことが目的です。
    ///
    /// 結合はネストしません（結合結果をさらに結合しても構成元は 1 段のまま）。
    /// スナップショット自身が構成元を持つことはないため、この往復で情報は落ちません。
    init(from decoder: any Decoder) throws {
        self.init(element: try CanvasElement(from: decoder))
    }

    func encode(to encoder: any Encoder) throws {
        try element.encode(to: encoder)
    }
}
