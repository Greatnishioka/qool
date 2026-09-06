/// 要素を重なり順のどこへ動かすか。
///
/// **`Canvas.elements` の並びがそのまま重なり順です。** 後ろの要素ほど手前に描かれ、
/// クリックも後ろから拾います（[CanvasSelectionService](../Services/CanvasSelectionService.swift)）。
nonisolated enum CanvasElementOrder: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// いちばん手前へ。
    case front
    /// 1 つ手前へ。
    case forward
    /// 1 つ奥へ。
    case backward
    /// いちばん奥へ。
    case back

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .front: return "最前面へ"
        case .forward: return "前面へ"
        case .backward: return "背面へ"
        case .back: return "最背面へ"
        }
    }

    var systemImage: String {
        switch self {
        case .front: return "arrow.up.to.line"
        case .forward: return "arrow.up"
        case .backward: return "arrow.down"
        case .back: return "arrow.down.to.line"
        }
    }
}
