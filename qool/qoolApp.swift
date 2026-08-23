import SwiftUI

@main
struct QoolApp: App {
    @StateObject private var viewModel = AppRootViewModel.bootstrap()

    var body: some Scene {
        // メニューバー項目。Dock には出さない（Info.plist の LSUIElement）。
        MenuBarExtra {
            MemoPanelView(viewModel: viewModel)
        } label: {
            Image(systemName: "square.on.square.dashed")
        }
        .menuBarExtraStyle(.window)
    }
}
