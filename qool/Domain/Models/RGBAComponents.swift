import Foundation

/// 色を実数の成分として表す。UI フレームワークに依存しない Domain の型。
struct RGBAComponents: Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red.clampedToUnitInterval
        self.green = green.clampedToUnitInterval
        self.blue = blue.clampedToUnitInterval
        self.opacity = opacity.clampedToUnitInterval
    }
}

private extension Double {
    var clampedToUnitInterval: Double {
        min(max(self, 0), 1)
    }
}
