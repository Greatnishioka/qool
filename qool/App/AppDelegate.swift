import AppKit

/// アプリの合成ルート。ViewModel を所有し、終了前に書き込みを確定させます。
///
/// **終了は `.terminateLater` で保留し、書き込み後に `reply` します。**
/// `willTerminateNotification` では非同期を待てず、セマフォ待機は MainActor を塞ぎます。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = AppRootViewModel.bootstrap()

    /// 終了要求の多重実行を防ぐ。`reply` は必ず 1 回だけ呼ぶ必要があります。
    private var isTerminating = false

    /// 書き込みを待つ上限。ファイル I/O が返らない場合（ネットワークボリュームなど）、
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
    /// 同期ファイル I/O は止められないため、時間切れでは結果を無視するだけです。
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
