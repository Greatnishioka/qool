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
