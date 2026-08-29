import Combine
import Foundation

@MainActor
final class AppRootViewModel: ObservableObject {
    /// この回数を超えて再試行が続いたら、表示を「原因を確認してほしい」側へ切り替えます。
    private static let attemptsBeforeEscalation = 2

    @Published private(set) var memos: [Memo] = []
    @Published var selectedMemo: Memo?
    @Published var cutoutDraft = ImageCutoutDraft()
    @Published var imageAdjustment = ImageAdjustment.default

    /// 保存の状態。失敗しているときだけ画面に出します。
    @Published private(set) var persistenceStatus: MemoPersistenceStatus = .ok

    /// 一覧を読み込めなかった。**「メモが 0 件」と区別する**ために持ちます。
    @Published private(set) var didFailToLoad = false

    private let loadMemosUseCase: LoadMemosUseCase
    private let createMemoUseCase: CreateMemoUseCase
    private let saveMemoUseCase: SaveMemoUseCase
    private let flushMemosUseCase: FlushMemosUseCase
    private let observeWriteStatesUseCase: ObserveWriteStatesUseCase
    private let elementFactory: CanvasElementFactory
    private var writeStateTask: Task<Void, Never>?

    init(
        loadMemosUseCase: LoadMemosUseCase,
        createMemoUseCase: CreateMemoUseCase,
        saveMemoUseCase: SaveMemoUseCase,
        flushMemosUseCase: FlushMemosUseCase,
        observeWriteStatesUseCase: ObserveWriteStatesUseCase,
        elementFactory: CanvasElementFactory
    ) {
        self.loadMemosUseCase = loadMemosUseCase
        self.createMemoUseCase = createMemoUseCase
        self.saveMemoUseCase = saveMemoUseCase
        self.flushMemosUseCase = flushMemosUseCase
        self.observeWriteStatesUseCase = observeWriteStatesUseCase
        self.elementFactory = elementFactory
        reload()
        observeWriteStates()
    }

    deinit {
        writeStateTask?.cancel()
    }

    /// 保存の状態は**実際の書き込み結果からのみ**更新します。保存要求を受け付けた時点で
    /// 成功扱いにすると、まとめ書きの中で失敗しても画面は正常なままになります。
    private func observeWriteStates() {
        writeStateTask = Task { [weak self] in
            guard let observeWriteStates = self?.observeWriteStatesUseCase else {
                return
            }

            for await state in observeWriteStates() {
                switch state {
                case .idle:
                    self?.persistenceStatus = .ok
                case let .retrying(attempt):
                    self?.persistenceStatus = attempt >= Self.attemptsBeforeEscalation ? .failing : .retrying
                case .failed:
                    self?.persistenceStatus = .failing
                }
            }
        }
    }

    /// 実アプリ用の組み立て。保存先はディスク。テストやプレビューでは
    /// `InMemoryMemoRepositoryInfrastructure` を渡した `bootstrap(repository:)` を使います。
    static func bootstrap() -> AppRootViewModel {
        // まとめ書きを挟む。flush はアプリ側で呼ぶ必要があります。
        let repository = DebouncedMemoRepositoryInfrastructure(wrapping: FileMemoRepositoryInfrastructure())

        return bootstrap(repository: repository, monitor: repository)
    }

    static func bootstrap(
        repository: any MemoRepositoryProtocol,
        monitor: (any MemoWriteMonitoringProtocol)? = nil
    ) -> AppRootViewModel {
        AppRootViewModel(
            loadMemosUseCase: LoadMemosUseCase(repository: repository),
            createMemoUseCase: CreateMemoUseCase(repository: repository),
            saveMemoUseCase: SaveMemoUseCase(repository: repository),
            flushMemosUseCase: FlushMemosUseCase(repository: repository),
            observeWriteStatesUseCase: ObserveWriteStatesUseCase(monitor: monitor),
            elementFactory: CanvasElementFactory()
        )
    }

    /// 全メモをディスクから読み直す。**起動時と、読み込み失敗からの再試行でのみ呼びます。**
    /// 保存後の一覧更新は `apply(_:)` がメモリ上で行います。
    func reload() {
        do {
            memos = try loadMemosUseCase()
            didFailToLoad = false
        } catch {
            // 読めなかったときに空配列を入れると「メモが 0 件」と区別できません。
            // 手元の内容はそのまま残します。
            didFailToLoad = true
        }
    }

    func createMemo() async -> Memo? {
        do {
            let memo = try await createMemoUseCase()
            apply(memo)
            selectedMemo = memo

            return memo
        } catch {
            return nil
        }
    }

    func open(_ memo: Memo) {
        selectedMemo = memo
    }

    func addElement(using tool: CanvasTool) async {
        guard var memo = selectedMemo, let element = elementFactory.makeElement(for: tool) else {
            return
        }

        memo.canvas.elements.append(element)
        await saveMemo(memo)
    }

    func saveMemo(_ memo: Memo) async {
        do {
            // 戻り値を使うのが要点。`SaveMemoUseCase` が更新日時を差し替えるため、
            // 引数の `memo` をそのまま一覧へ入れると更新日時が古いままになります。
            let savedMemo = try await saveMemoUseCase(memo)

            selectedMemo = savedMemo
            apply(savedMemo)
        } catch {
            // 画面上は編集結果を保ちます。失敗は状態表示で伝えます。
            selectedMemo = memo
            apply(memo)
        }
    }

    func updateAdjustment(_ adjustment: ImageAdjustment) {
        imageAdjustment = adjustment
    }

    func commitImageMemo() async {
        await addElement(using: .image)
        cutoutDraft = ImageCutoutDraft()
        imageAdjustment = .default
    }

    /// 保留している書き込みを確定する。**アプリ終了時に必ず呼んでください。**
    ///
    /// - Returns: すべて書けたら `true`。**終了してよいかの判断に使います。**
    @discardableResult
    func flush() async -> Bool {
        do {
            try await flushMemosUseCase()

            return true
        } catch {
            return false
        }
    }

    /// 画面の「再試行」から呼びます。
    func retryFailedWork() async {
        if didFailToLoad {
            reload()
        }

        _ = await flush()
    }

    // MARK: -

    /// 保存済みのメモを一覧へ反映する。並び順は `MemoRepositoryProtocol.loadMemos()` と同じ
    /// **更新日時の降順**に揃えます。ずれると再起動の前後で一覧の並びが変わります。
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
