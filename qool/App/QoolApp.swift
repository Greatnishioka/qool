import SwiftUI

/// **ダークモードには対応しません。** キャンバスが紙を模した白基調で、
/// 外観に追随させると背景・パネル・ツールドックだけが暗くなり混ざります。
@main
struct QoolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // メニューバー項目。Dock には出さない（Info.plist の LSUIElement）。
        MenuBarExtra {
            MemoPanelView(viewModel: appDelegate.viewModel)
                .preferredColorScheme(.light)
        } label: {
            Image(systemName: "square.on.square.dashed")
        }
        .menuBarExtraStyle(.window)

        // S5。パネル内で画面遷移せず、**別ウィンドウ**で開きます。
        WindowGroup(for: Memo.ID.self) { $memoID in
            CanvasWindowView(memoID: memoID, rootViewModel: appDelegate.viewModel)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 1000, height: 700)
    }
}
