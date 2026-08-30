/// ぼかしをどちら側へかけるか。
nonisolated enum ImageBlurDirection: String, CaseIterable, Identifiable, Hashable, Codable {
    case outward
    case inward
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .outward:
            "外側"
        case .inward:
            "内側"
        case .both:
            "両側"
        }
    }
}
