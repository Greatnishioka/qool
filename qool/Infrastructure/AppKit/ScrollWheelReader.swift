import AppKit
import SwiftUI

/// マウスホイール / トラックパッドの 2 本指スクロールを拾う。
///
/// **SwiftUI にホイールを受け取る手段がありません。** `ScrollView` の中でしか使えないため、
/// キャンバス操作に使うには AppKit を挟む必要があります。
///
/// **クリックは奪いません。** `hitTest` が常に `nil` を返すので、重ねて置いても
/// 下の SwiftUI のジェスチャがそのまま動きます。そのぶん通常の経路では
/// スクロールも届かなくなるため、イベントは監視で受け取ります。
struct ScrollWheelReader: NSViewRepresentable {
    let onScroll: (ScrollWheelInput) -> Void

    func makeNSView(context: Context) -> ScrollWheelCatchingView {
        let view = ScrollWheelCatchingView()
        view.onScroll = onScroll

        return view
    }

    func updateNSView(_ nsView: ScrollWheelCatchingView, context: Context) {
        nsView.onScroll = onScroll
    }
}
