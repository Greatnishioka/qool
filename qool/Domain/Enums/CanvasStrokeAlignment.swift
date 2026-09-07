/// 枠線を形のどちら側へ広げるか。
///
/// **既定は `center` です。** 描画は元から中央揃えだったので、
/// 既存のメモを読み込んでも見た目が変わりません。
nonisolated enum CanvasStrokeAlignment: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    /// 形の内側だけへ広げる。要素の占める大きさは変わりません。
    case inside
    /// 形の線を中心に、内と外へ半分ずつ広げる。
    case center
    /// 形の外側だけへ広げる。**要素は枠線のぶん大きく見えます。**
    case outside

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inside: return "内側"
        case .center: return "中央"
        case .outside: return "外側"
        }
    }
}
