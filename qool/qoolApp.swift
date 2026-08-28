import AppKit
import SwiftUI

@main
struct QoolApp: App {
    @StateObject private var viewModel: AppRootViewModel

    init() {
        let viewModel = AppRootViewModel.bootstrap()
        _viewModel = StateObject(wrappedValue: viewModel)

        // 書き込みはまとめられるため、終了前に確定させないと最後の編集が失われます。
        // `MenuBarExtra` には確実な「閉じた」通知がないので、
        // アプリ終了とパネルの `onDisappear` の両方で受けます。
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                viewModel.flush()
            }
        }
    }

    var body: some Scene {
        // メニューバー項目。Dock には出さない（Info.plist の LSUIElement）。
        MenuBarExtra {
            MemoPanelView(viewModel: viewModel)
                .onDisappear {
                    viewModel.flush()
                }
        } label: {
            Image(systemName: "square.on.square.dashed")
        }
        .menuBarExtraStyle(.window)
    }
}
