nonisolated enum CanvasElementKind: String, CaseIterable, Identifiable, Hashable, Codable {
    case rectangle
    case path
    case line
    case text
    case imageCutout

    var id: String { rawValue }
}
