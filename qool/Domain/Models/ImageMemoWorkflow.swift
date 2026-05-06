import Foundation

struct ImageCutoutDraft: Equatable, Hashable {
    var pathPoints: [NormalizedPoint]
    var sourceDescription: String

    init(pathPoints: [NormalizedPoint] = [], sourceDescription: String = "未選択の画像") {
        self.pathPoints = pathPoints
        self.sourceDescription = sourceDescription
    }
}

struct ImageAdjustment: Equatable, Hashable {
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

struct NormalizedPoint: Equatable, Hashable {
    var x: Double
    var y: Double
}
