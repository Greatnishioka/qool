import SwiftUI

/// Domain の色を SwiftUI の `Color` へ変換する。
/// この変換は Presentation 層の責務であり、Domain は UI フレームワークを知らない。
extension RGBAComponents {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }

    /// `ColorPicker` などから受け取った `Color` を Domain の成分へ落とす。
    ///
    /// 動的色やパターン色など sRGB へ変換できない色があるため failable にしている。
    /// 変換できなかったものを黒として保存すると、色が失われたことに気づけない。
    init?(_ color: Color) {
        guard let sRGBColor = NSColor(color).usingColorSpace(.sRGB) else {
            return nil
        }

        self.init(
            red: Double(sRGBColor.redComponent),
            green: Double(sRGBColor.greenComponent),
            blue: Double(sRGBColor.blueComponent),
            opacity: Double(sRGBColor.alphaComponent)
        )
    }
}
