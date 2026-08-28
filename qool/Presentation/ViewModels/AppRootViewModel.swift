import Combine
import Foundation

@MainActor
final class AppRootViewModel: ObservableObject {
    @Published private(set) var memos: [Memo] = []
    @Published var selectedMemo: Memo?
    @Published var cutoutDraft = ImageCutoutDraft()
    @Published var imageAdjustment = ImageAdjustment.default

    private let loadMemosUseCase: LoadMemosUseCase
    private let createMemoUseCase: CreateMemoUseCase
    private let saveMemoUseCase: SaveMemoUseCase
    private let flushMemosUseCase: FlushMemosUseCase
    private let elementFactory: CanvasElementFactory

    init(
        loadMemosUseCase: LoadMemosUseCase,
        createMemoUseCase: CreateMemoUseCase,
        saveMemoUseCase: SaveMemoUseCase,
        flushMemosUseCase: FlushMemosUseCase,
        elementFactory: CanvasElementFactory
    ) {
        self.loadMemosUseCase = loadMemosUseCase
        self.createMemoUseCase = createMemoUseCase
        self.saveMemoUseCase = saveMemoUseCase
        self.flushMemosUseCase = flushMemosUseCase
        self.elementFactory = elementFactory
        reload()
    }

    /// 実アプリ用の組み立て。保存先はディスク。
    ///
    /// テストやプレビューでは `InMemoryMemoRepository` を渡した
    /// `bootstrap(repository:)` を使ってください。
    static func bootstrap() -> AppRootViewModel {
        // まとめ書きを挟む。flush はアプリ側で呼ぶ必要があります。
        bootstrap(repository: DebouncedMemoRepository(wrapping: FileMemoRepository()))
    }

    static func bootstrap(repository: MemoRepository) -> AppRootViewModel {
        AppRootViewModel(
            loadMemosUseCase: LoadMemosUseCase(repository: repository),
            createMemoUseCase: CreateMemoUseCase(repository: repository),
            saveMemoUseCase: SaveMemoUseCase(repository: repository),
            flushMemosUseCase: FlushMemosUseCase(repository: repository),
            elementFactory: CanvasElementFactory()
        )
    }

    /// 全メモをディスクから読み直す。
    ///
    /// **起動時のみ呼びます。** 保存のたびに呼ぶと、1 件の書き込みに対して
    /// 全メモの読み込みと復号が走ります（スライダー操作 1 目盛りごとに全件、という状態でした）。
    /// 保存後の一覧更新は `apply(_:)` がメモリ上で行います。
    func reload() {
        memos = loadMemosUseCase.execute()
    }

    func createMemo() -> Memo {
        let memo = createMemoUseCase.execute()
        apply(memo)
        selectedMemo = memo

        return memo
    }

    func open(_ memo: Memo) {
        selectedMemo = memo
    }

    func addElement(using tool: CanvasTool) {
        guard var memo = selectedMemo, let element = elementFactory.makeElement(for: tool) else {
            return
        }

        memo.canvas.elements.append(element)
        saveMemo(memo)
    }

    func saveMemo(_ memo: Memo) {
        // 戻り値を使うのが要点。`execute` が更新日時を差し替えるため、
        // 引数の `memo` をそのまま一覧へ入れると更新日時が古いままになります。
        let savedMemo = saveMemoUseCase.execute(memo)

        selectedMemo = savedMemo
        apply(savedMemo)
    }

    func updateAdjustment(_ adjustment: ImageAdjustment) {
        imageAdjustment = adjustment
    }

    func commitImageMemo() {
        addElement(using: .image)
        cutoutDraft = ImageCutoutDraft()
        imageAdjustment = .default
    }

    /// 保留している書き込みを確定する。
    ///
    /// **アプリ終了時とパネルを閉じるときに必ず呼んでください。**
    /// 呼び忘れると、まとめ書き待ちの編集が失われます。
    func flush() {
        flushMemosUseCase.execute()
    }

    /// 保存済みのメモを一覧へ反映する。既にあれば置き換え、無ければ追加する。
    ///
    /// 並び順は `MemoRepository.loadMemos()` と同じ **更新日時の降順**に揃えます。
    /// ここがずれると、再起動の前後で一覧の並びが変わってしまいます。
    private func apply(_ memo: Memo) {
        var updatedMemos = memos

        if let index = updatedMemos.firstIndex(where: { $0.id == memo.id }) {
            updatedMemos[index] = memo
        } else {
            updatedMemos.append(memo)
        }

        memos = updatedMemos.sorted { $0.updatedAt > $1.updatedAt }
    }
}
