nonisolated enum CanvasTool: String, CaseIterable, Identifiable, Hashable {
    case select = "選択"
    case rectangle = "矩形"
    case path = "パス"
    case line = "直線"
    case text = "テキスト"
    case image = "画像"

    var id: String { rawValue }
}
