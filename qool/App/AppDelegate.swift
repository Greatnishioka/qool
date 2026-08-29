import AppKit

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

    /// 書き込みを待つ上限。これを超えたら保存失敗として扱います。
    ///
    /// ファイル I/O 自体が返らない場合（ネットワークボリュームなど）、
    /// **これがないと `.terminateLater` のまま永久に終了できなくなります。**
    private static let flushTimeout = Duration.seconds(5)

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else {
            return .terminateLater
        }

        isTerminating = true

        Task { [viewModel] in
            let didPersist = await Self.flush(viewModel, within: Self.flushTimeout)

            // 保存できていないなら終了を中止し、失敗表示を残したままにします。
            // 未保存の編集を捨てないことを優先する判断です。
            self.isTerminating = false
            sender.reply(toApplicationShouldTerminate: didPersist)
        }

        return .terminateLater
    }

    /// 書き込みと時間切れを競争させ、**先に決まったほうを採用**します。
    ///
    /// 時間切れになっても書き込みタスク自体は止められません（同期ファイル I/O は
    /// キャンセルできないため）。結果を無視するだけです。
    /// それでも「終了できなくなる」よりは良い、という判断です。
    private static func flush(
        _ viewModel: AppRootViewModel,
        within timeout: Duration
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await viewModel.flush() }
            group.addTask {
                try? await Task.sleep(for: timeout)

                return false
            }

            let didPersist = await group.next() ?? false
            group.cancelAll()

            return didPersist
        }
    }
}
