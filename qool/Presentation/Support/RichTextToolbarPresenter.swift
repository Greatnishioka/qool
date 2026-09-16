import Combine

/// 書式の道具を、選んだ範囲の上へ出し入れする。
///
/// **要素に重ねずに別の窓へ出します。** 貼ったメモの窓は輪郭の外でクリックを
/// 素通しし、大きさに上限があり、中身が縮小されています。その中へ置くと
/// 押せない・切れる・読めないの 3 つが同時に起きます
/// （[#21](https://github.com/Greatnishioka/qool/issues/21) の段階 5）。
///
/// [FloatingMemoPresenter](FloatingMemoPresenter.swift) と同じ形です。
/// ViewModel の値を購読し、ウィンドウの開け閉めは Infrastructure へ渡します。
@MainActor
final class RichTextToolbarPresenter {
    private let viewModel: AppRootViewModel
    private let panels = RichTextToolbarPanelManager()
    private var observer: AnyCancellable?

    init(viewModel: AppRootViewModel) {
        self.viewModel = viewModel
    }

    /// 起動時に一度だけ呼びます。
    func start() {
        observer = viewModel.$richTextToolbar.sink { [weak self] request in
            self?.apply(request)
        }
    }

    // MARK: -

    private func apply(_ request: RichTextToolbarRequest?) {
        guard let request else {
            panels.hide()

            return
        }

        panels.show(
            RichTextToolbar(onStyle: request.onStyle, onColor: request.onColor),
            near: request.selectionRect
        )
    }
}
