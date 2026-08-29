nonisolated struct ImageAdjustment: Equatable, Hashable {
    var opacity: Double
    var brightness: Double
    var padding: Double
    var blur: Double

    static let `default` = ImageAdjustment(
        opacity: 0.8,
        brightness: 0,
        padding: 12,
        blur: 0
    )
}
