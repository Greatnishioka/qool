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
                // 終了処理は待ってくれないため、書き込みが終わるまでここで止めます。
                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    await viewModel.flush()
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + 2)
            }
        }
    }

    var body: some Scene {
        // メニューバー項目。Dock には出さない（Info.plist の LSUIElement）。
        MenuBarExtra {
            MemoPanelView(viewModel: viewModel)
                .onDisappear {
                    Task { await viewModel.flush() }
                }
        } label: {
            Image(systemName: "square.on.square.dashed")
        }
        .menuBarExtraStyle(.window)
    }
}
