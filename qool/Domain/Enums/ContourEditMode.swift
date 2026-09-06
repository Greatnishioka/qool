/// 切り抜きの手直しで、なぞった領域をどう扱うか。
nonisolated enum ContourEditMode: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    /// 輪郭に足す（ペン / 投げ縄で追加）。
    case add
    /// 輪郭から引く（消しゴム / 投げ縄で削除）。
    case subtract

    var id: String { rawValue }
}
