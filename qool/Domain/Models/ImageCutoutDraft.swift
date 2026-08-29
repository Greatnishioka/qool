nonisolated struct ImageCutoutDraft: Equatable, Hashable {
    var pathPoints: [NormalizedPoint]
    var sourceDescription: String

    init(pathPoints: [NormalizedPoint] = [], sourceDescription: String = "未選択の画像") {
        self.pathPoints = pathPoints
        self.sourceDescription = sourceDescription
    }
}
