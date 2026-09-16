import CoreGraphics

/// 書式の道具を画面のどこへ置くかを決める。
///
/// **純粋な計算なので Domain に置いています。** 使うのはウィンドウを開け閉めする
/// Infrastructure で、そちらから Presentation を参照させないためです
/// （[MarkdownSelectionGuard](MarkdownSelectionGuard.swift) と同じ理由）。
///
/// **画面座標（左下原点）で計算します。** AppKit のウィンドウ位置がその空間なので、
/// ここで左上原点に直すと置く直前でもう一度ひっくり返すことになります。
nonisolated struct RichTextToolbarPlacement {
    /// 選んだ範囲との隙間。
    ///
    /// **窓の縁は道具の縁ではありません。** 影が切れないよう、窓には余白を入れて
    /// あります（`RichTextToolbarPanelManager`）。見た目の隙間はその分だけ広くなります。
    private static let gap: CGFloat = 2

    /// 画面の端から空ける余白。
    private static let margin: CGFloat = 4

    /// 窓の左下位置を返す。
    ///
    /// **既定は選択の上です。** 下に出すと、押そうとした指が次の行を隠します。
    /// 画面の上端に収まらないときだけ下へ回します。
    func origin(
        for selectionRect: CGRect,
        panelSize: CGSize,
        within visibleFrame: CGRect
    ) -> CGPoint {
        let above = selectionRect.maxY + Self.gap
        let below = selectionRect.minY - Self.gap - panelSize.height
        let fitsAbove = above + panelSize.height + Self.margin <= visibleFrame.maxY

        return CGPoint(
            x: clamp(
                selectionRect.midX - panelSize.width / 2,
                from: visibleFrame.minX + Self.margin,
                to: visibleFrame.maxX - Self.margin - panelSize.width
            ),
            y: clamp(
                fitsAbove ? above : below,
                from: visibleFrame.minY + Self.margin,
                to: visibleFrame.maxY - Self.margin - panelSize.height
            )
        )
    }

    /// **上限が下限を下回るときは下限を返します。** 画面より大きい道具や、
    /// 極端に狭い作業領域で `min(max(…))` の順序が壊れるのを防ぎます。
    private func clamp(_ value: CGFloat, from lower: CGFloat, to upper: CGFloat) -> CGFloat {
        guard upper > lower else {
            return lower
        }

        return min(max(value, lower), upper)
    }
}
