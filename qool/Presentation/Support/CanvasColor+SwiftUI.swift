import SwiftUI

/// Domain の色を SwiftUI の `Color` へ変換する。
/// この変換は Presentation 層の責務であり、Domain は UI フレームワークを知らない。
extension CanvasColor {
    var swiftUIColor: Color {
        let components = components
        return Color(
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: components.opacity
        )
    }
}

extension RGBAComponents {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }

    /// `ColorPicker` などから受け取った `Color` を Domain の成分へ落とす。
    init(_ color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.sRGB)
        self.init(
            red: Double(nsColor?.redComponent ?? 0),
            green: Double(nsColor?.greenComponent ?? 0),
            blue: Double(nsColor?.blueComponent ?? 0),
            opacity: Double(nsColor?.alphaComponent ?? 1)
        )
    }
}
