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

        // S5。パネル内で画面遷移せず、**別ウィンドウ**で開きます。
        WindowGroup(for: Memo.ID.self) { $memoID in
            CanvasWindowView(memoID: memoID, rootViewModel: appDelegate.viewModel)
        }
        .defaultSize(width: 1000, height: 700)
    }
}
