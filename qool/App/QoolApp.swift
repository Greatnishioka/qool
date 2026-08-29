import SwiftUI

@main
struct QoolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // メニューバー項目。Dock には出さない（Info.plist の LSUIElement）。
        MenuBarExtra {
            MemoPanelView(viewModel: appDelegate.viewModel)
        } label: {
            Image(systemName: "square.on.square.dashed")
        }
        .menuBarExtraStyle(.window)
    }
}
