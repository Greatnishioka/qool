import AppKit
import SwiftUI

/// アプリの合成ルート。ViewModel を所有し、終了前に書き込みを確定させます。
///
/// **ViewModel をここで持つのが要点です。** 以前は `App` が持ち、View が現れてから
/// デリゲートへ配線していましたが、それだとパネルを一度も開かずに終了した場合に
/// 配線されないままになります（今はパネル以外から編集できないため実害は出ませんが、
/// ホットキーからメモを作れるようにした時点で未保存の編集を失います）。
///
/// また `willTerminateNotification` では非同期処理を待てません。
/// **`.terminateLater` を返して終了を保留し、書き込み後に `reply` する**のが正しい形です。
/// 以前は `DispatchSemaphore` で待っていましたが、`Task` が MainActor を継承するため
/// **待機がその MainActor を塞いでデッドロックし、flush が一度も実行されていませんでした。**
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = AppRootViewModel.bootstrap()

    /// 終了要求の多重実行を防ぐ。`reply` は必ず 1 回だけ呼ぶ必要があります。
    private var isTerminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else {
            return .terminateLater
        }

        isTerminating = true

        Task { [viewModel] in
            let didPersist = await viewModel.flush()

            // 保存できていないなら終了を中止し、失敗表示を残したままにします。
            // 未保存の編集を捨てないことを優先する判断です。
            self.isTerminating = false
            sender.reply(toApplicationShouldTerminate: didPersist)
        }

        return .terminateLater
    }
}

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
