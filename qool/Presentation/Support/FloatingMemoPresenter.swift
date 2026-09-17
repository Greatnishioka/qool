import Combine
import Foundation

/// 机の上の付箋を、一覧の状態に合わせて開閉する。
///
/// **`StickyNote` の存在が唯一の正です。** 出す／はがすはレコードを足す・消すだけで、
/// ウィンドウの開閉はここが追従します。二重に状態を持つと、保存内容と画面が食い違います。
///
/// **形は雛形が持ち、本文は付箋が持ちます**
/// （[#29](https://github.com/Greatnishioka/qool/issues/29)）。
/// 描くたびに雛形の canvas へ本文を差し込んで組み立てます。
@MainActor
final class FloatingMemoPresenter {
    private let viewModel: AppRootViewModel
    private let buildOutline = BuildFloatingMemoOutlineUseCase()
    private let composer = StickyNoteCanvasComposer()
    private let windows = FloatingMemoWindowManager()

    /// 直前に描いた内容。**ドラッグ中の位置保存で中身まで作り直さない**ために持ちます。
    private var presentedCanvases: [StickyNote.ID: Canvas] = [:]

    /// 本文を書き換えている最中の付箋。**この間は窓を作り直しません。**
    private var editingNoteIDs: Set<StickyNote.ID> = []

    private var observers: Set<AnyCancellable> = []

    init(viewModel: AppRootViewModel) {
        self.viewModel = viewModel
    }

    /// 起動時に一度だけ呼びます。出してあった付箋を復元し、以後の変更へ追従します。
    ///
    /// **雛形と付箋の両方を見ます。** 雛形を直すと付箋の形も変わるためです。
    func start() {
        synchronize()

        viewModel.$memos
            .sink { [weak self] _ in self?.synchronize() }
            .store(in: &observers)

        viewModel.$stickyNotes
            .sink { [weak self] _ in self?.synchronize() }
            .store(in: &observers)
    }

    /// 付箋を出せるのは要素のある雛形だけです。空のキャンバスには形がありません。
    func canCreateStickyNote(from template: Memo) -> Bool {
        buildOutline(from: template.canvas) != nil
    }

    /// 雛形から付箋を 1 枚出す。**何枚でも出せます。**
    func createStickyNote(from template: Memo) {
        guard let outline = buildOutline(from: template.canvas) else {
            return
        }

        // 置き場所は今までと同じ決め方（画面中央からカスケード）です。
        let origin = windows.nextOrigin(for: outline)
        Task { await viewModel.createStickyNote(from: template, at: origin) }
    }

    /// 付箋をはがす。**レコードごと消します。** 位置だけ残った状態を作りません。
    func removeStickyNote(_ noteID: StickyNote.ID) {
        Task { await viewModel.deleteStickyNote(id: noteID) }
    }

    /// その雛形から出ている付箋。ホットキーの切り替えに使います。
    func stickyNotes(of templateID: Memo.ID) -> [StickyNote] {
        viewModel.stickyNotes.filter { $0.templateID == templateID }
    }

    // MARK: -

    private func synchronize() {
        let notes = viewModel.stickyNotes

        for note in notes {
            present(note)
        }

        for noteID in windows.showingNoteIDs.subtracting(notes.map(\.id)) {
            close(noteID)
        }
    }

    private func present(_ note: StickyNote) {
        guard let template = viewModel.memos.first(where: { $0.id == note.templateID }),
              let outline = buildOutline(from: template.canvas) else {
            // 雛形の要素をすべて消すと形がなくなります。**付箋ごと片付けます。**
            // 残すと一覧に出続け、要素を足し直した瞬間に、出していない付箋が現れます。
            close(note.id)
            removeStickyNote(note.id)

            return
        }

        // **書き換え中は中身を差し替えません。** 1 文字打つたびに保存が走り、
        // その反映で `rootView` が入れ替わると、キャレットと日本語変換が飛びます。
        // **`presentedCanvases` もわざと進めません。** 進めると、抜けたあとに
        // 「同じ内容だ」と判断して当て直しが起きなくなります。
        guard !editingNoteIDs.contains(note.id) else {
            return
        }

        let canvas = composer.canvas(for: note, from: template.canvas)

        guard presentedCanvases[note.id] != canvas || !windows.isShowing(note.id) else {
            return
        }

        presentedCanvases[note.id] = canvas
        windows.show(
            noteID: note.id,
            outline: outline,
            origin: note.origin,
            content: FloatingMemoView(
                canvas: canvas,
                templateID: template.id,
                outline: outline,
                imageStore: viewModel.imageStore,
                maskStore: viewModel.maskStore,
                onEdit: { [weak self] in self?.viewModel.requestCanvas(for: template.id) },
                onRemove: { [weak self] in self?.removeStickyNote(note.id) },
                onTextChange: { [weak self] elementID, text in
                    self?.updateText(text, of: elementID, in: note.id)
                },
                onEditingChange: { [weak self] isEditing in
                    self?.setEditing(isEditing, for: note.id)
                },
                onToolbar: { [weak self] owner, request in
                    self?.viewModel.updateRichTextToolbar(request, from: owner)
                }
            ),
            onMove: { [weak self] movedOrigin in
                self?.updateOrigin(movedOrigin, of: note.id)
            }
        )
    }

    /// 書き換えた本文を保存する。
    ///
    /// **一覧の最新から組み立てます。** 窓が抱えている付箋は開いた時点の写しなので、
    /// そのまま書くと、その間に変わった他の値を巻き戻します。
    private func updateText(_ text: String, of elementID: CanvasElement.ID, in noteID: StickyNote.ID) {
        guard var note = viewModel.stickyNotes.first(where: { $0.id == noteID }) else {
            return
        }

        note.texts[elementID] = text

        Task { await viewModel.saveStickyNote(note) }
    }

    private func updateOrigin(_ origin: CGPoint, of noteID: StickyNote.ID) {
        guard var note = viewModel.stickyNotes.first(where: { $0.id == noteID }), note.origin != origin else {
            return
        }

        note.origin = origin

        Task { await viewModel.saveStickyNote(note) }
    }

    /// 書き換えの出入り。**抜けた時点で一度だけ窓を当て直します。**
    private func setEditing(_ isEditing: Bool, for noteID: StickyNote.ID) {
        guard editingNoteIDs.contains(noteID) != isEditing else {
            return
        }

        if isEditing {
            editingNoteIDs.insert(noteID)
            // **アプリを前面へ出します。** 出さないと入力メソッドが文字を渡してきません。
            windows.activate(noteID)

            return
        }

        editingNoteIDs.remove(noteID)
        synchronize()
    }

    private func close(_ noteID: StickyNote.ID) {
        presentedCanvases.removeValue(forKey: noteID)
        editingNoteIDs.remove(noteID)
        windows.close(noteID)
    }
}
