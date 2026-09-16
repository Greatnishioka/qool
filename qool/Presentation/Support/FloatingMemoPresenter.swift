import Combine
import Foundation

/// デスクトップに貼ったメモを、一覧の状態に合わせて開閉する。
///
/// **`Memo.floatingOrigin` が唯一の正です。** 貼る／はがすはこの値を書き換えるだけで、
/// ウィンドウの開閉はここが追従します。二重に状態を持つと、保存内容と画面が食い違います。
@MainActor
final class FloatingMemoPresenter {
    private let viewModel: AppRootViewModel
    private let buildOutline = BuildFloatingMemoOutlineUseCase()
    private let updateElementUseCase = UpdateCanvasElementUseCase()
    private let windows = FloatingMemoWindowManager()

    /// 直前に描いた内容。**ドラッグ中の位置保存で中身まで作り直さない**ために持ちます。
    private var presentedCanvases: [Memo.ID: Canvas] = [:]

    /// 本文を書き換えている最中のメモ。**この間は窓を作り直しません。**
    private var editingMemoIDs: Set<Memo.ID> = []

    private var memosObserver: AnyCancellable?

    init(viewModel: AppRootViewModel) {
        self.viewModel = viewModel
    }

    /// 起動時に一度だけ呼びます。貼ってあったメモを復元し、以後の変更へ追従します。
    func start() {
        synchronize(with: viewModel.memos)
        memosObserver = viewModel.$memos.sink { [weak self] memos in
            self?.synchronize(with: memos)
        }
    }

    /// 貼れるのは要素のあるメモだけです。空のキャンバスには形がありません。
    func canPin(_ memo: Memo) -> Bool {
        buildOutline(from: memo.canvas) != nil
    }

    func pin(_ memo: Memo) {
        guard let outline = buildOutline(from: memo.canvas) else {
            return
        }

        let origin = windows.nextOrigin(for: outline)
        Task { await viewModel.updateFloatingOrigin(origin, for: memo.id) }
    }

    func unpin(_ memoID: Memo.ID) {
        Task { await viewModel.updateFloatingOrigin(nil, for: memoID) }
    }

    // MARK: -

    private func synchronize(with memos: [Memo]) {
        let floatingMemos = memos.filter { $0.floatingOrigin != nil }

        for memo in floatingMemos {
            present(memo)
        }

        for memoID in windows.showingMemoIDs.subtracting(floatingMemos.map(\.id)) {
            close(memoID)
        }
    }

    private func present(_ memo: Memo) {
        guard let origin = memo.floatingOrigin, let outline = buildOutline(from: memo.canvas) else {
            // 要素をすべて消したメモには形がありません。**ウィンドウを閉じるだけでなく
            // `floatingOrigin` も戻します。** 残すと一覧に「はがす」が出続け、
            // 要素を足し直した瞬間に、貼り直していないのに現れます。
            close(memo.id)

            if memo.floatingOrigin != nil {
                unpin(memo.id)
            }

            return
        }

        // **書き換え中は中身を差し替えません。** 1 文字打つたびに保存が走り、
        // その反映で `rootView` が入れ替わると、キャレットと日本語変換が飛びます。
        // **`presentedCanvases` もわざと進めません。** 進めると、抜けたあとに
        // 「同じ内容だ」と判断して当て直しが起きなくなります。
        guard !editingMemoIDs.contains(memo.id) else {
            return
        }

        guard presentedCanvases[memo.id] != memo.canvas || !windows.isShowing(memo.id) else {
            return
        }

        presentedCanvases[memo.id] = memo.canvas
        windows.show(
            memoID: memo.id,
            outline: outline,
            origin: origin,
            content: FloatingMemoView(
                memo: memo,
                outline: outline,
                imageStore: viewModel.imageStore,
                maskStore: viewModel.maskStore,
                onEdit: { [weak self] in self?.viewModel.requestCanvas(for: memo.id) },
                onRemove: { [weak self] in self?.unpin(memo.id) },
                onTextChange: { [weak self] elementID, text in
                    self?.updateText(text, of: elementID, in: memo.id)
                },
                onEditingChange: { [weak self] isEditing in
                    self?.setEditing(isEditing, for: memo.id)
                },
                onToolbar: { [weak self] owner, request in
                    self?.viewModel.updateRichTextToolbar(request, from: owner)
                }
            ),
            onMove: { [weak self] movedOrigin in
                Task { await self?.viewModel.updateFloatingOrigin(movedOrigin, for: memo.id) }
            }
        )
    }

    /// 貼ったまま書き換えた本文を保存する。
    ///
    /// **一覧の最新から組み立てます。** 窓が抱えている `memo` は貼った時点の写しなので、
    /// そのまま書くと、その間に変わった他の値を巻き戻します。
    private func updateText(_ text: String, of elementID: CanvasElement.ID, in memoID: Memo.ID) {
        guard var memo = viewModel.memos.first(where: { $0.id == memoID }) else {
            return
        }

        updateElementUseCase(in: &memo.canvas.elements, id: elementID) { element in
            element.text = text
        }

        Task { await viewModel.saveMemo(memo) }
    }

    /// 書き換えの出入り。**抜けた時点で一度だけ窓を当て直します。**
    private func setEditing(_ isEditing: Bool, for memoID: Memo.ID) {
        guard editingMemoIDs.contains(memoID) != isEditing else {
            return
        }

        if isEditing {
            editingMemoIDs.insert(memoID)
            // **アプリを前面へ出します。** 出さないと入力メソッドが文字を渡してきません。
            windows.activate(memoID)

            return
        }

        editingMemoIDs.remove(memoID)
        synchronize(with: viewModel.memos)
    }

    private func close(_ memoID: Memo.ID) {
        presentedCanvases.removeValue(forKey: memoID)
        editingMemoIDs.remove(memoID)
        windows.close(memoID)
    }
}
