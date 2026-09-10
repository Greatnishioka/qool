import AppKit
import SwiftUI

/// スペースキーが押されているかを見る。**手のひらツールの代わり**です。
///
/// **押下は握り潰します。** スペースは既定でフォーカス中のボタンを押すため、
/// そのまま流すと「適用」などが動いてしまいます。
struct SpaceKeyReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> SpaceKeyWatchingView {
        let view = SpaceKeyWatchingView()
        view.onChange = onChange

        return view
    }

    func updateNSView(_ nsView: SpaceKeyWatchingView, context: Context) {
        nsView.onChange = onChange
    }
}
