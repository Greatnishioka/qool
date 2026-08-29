import Foundation

/// 色を実数の成分として表す。成分は必ず `0...1` に収まり、非有限値を含まない。
/// この不変条件を初期化後も保つため、プロパティは `let` にしている。
nonisolated struct RGBAComponents: Equatable, Hashable, Codable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    /// 範囲外の値は `0...1` に丸め、非有限値は 0 として扱う。
    /// NaN を素通しさせると `.nan != .nan` であるため `Equatable` の反射律が壊れる。
    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = Self.normalized(red)
        self.green = Self.normalized(green)
        self.blue = Self.normalized(blue)
        self.opacity = Self.normalized(opacity)
    }

    private static func normalized(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }

        return min(max(value, 0), 1)
    }
}
