import AppKit
import SwiftUI

/// メニューバーのアイコン。
///
/// **キャンバスを開く要求もここで受けます。** `openWindow` は View からしか呼べず、
/// メニューバーのラベルは**パネルを閉じていても生きている**数少ない View だからです。
struct MenuBarLabel: View {
    @ObservedObject var viewModel: AppRootViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "square.on.square.dashed")
            .onChange(of: viewModel.canvasRequest) { _, memoID in
                guard let memoID else {
                    return
                }

                viewModel.clearCanvasRequest()
                openWindow(value: memoID)
                // `LSUIElement` のアプリは前面に出ないため、明示的に呼びます。
                NSApp.activate()
            }
    }
}
