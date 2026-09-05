import CoreGraphics

/// なぞった点列を、切り抜きの輪郭へ整える。
///
/// 抽出器（被写体マスクなど）はまだ移植していないため、**手描きのなぞりだけ**を扱います。
/// [ContourSmoother](../../../Domain/Services/ContourSmoother.swift) に通すと、
/// トゲが減り、直線は直線に寄り、角を残したまま滑らかになります。
nonisolated struct BuildCutoutContourUseCase {
    /// 面として成立する最小の点数。これ未満だとマスクが空になります。
    static let minimumPointCount = 3

    private let smoother: ContourSmoother

    init(smoother: ContourSmoother = ContourSmoother()) {
        self.smoother = smoother
    }

    /// - Parameter tracePoints: 画像の表示矩形を基準にした正規化座標（`0...1`）。
    /// - Returns: 整えた輪郭。点が足りなければ空。
    func callAsFunction(tracePoints: [CGPoint]) -> [CanvasPathContour] {
        guard tracePoints.count >= Self.minimumPointCount else {
            return []
        }

        let polishedPoints = smoother.polished(tracePoints)
        guard polishedPoints.count >= Self.minimumPointCount else {
            return []
        }

        return [
            CanvasPathContour(
                points: polishedPoints.map { NormalizedPoint(x: Double($0.x), y: Double($0.y)) },
                isClosed: true
            )
        ]
    }
}
