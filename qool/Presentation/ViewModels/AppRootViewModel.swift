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
    private let elementFactory: CanvasElementFactory

    init(
        loadMemosUseCase: LoadMemosUseCase,
        createMemoUseCase: CreateMemoUseCase,
        saveMemoUseCase: SaveMemoUseCase,
        elementFactory: CanvasElementFactory
    ) {
        self.loadMemosUseCase = loadMemosUseCase
        self.createMemoUseCase = createMemoUseCase
        self.saveMemoUseCase = saveMemoUseCase
        self.elementFactory = elementFactory
        reload()
    }

    static func bootstrap() -> AppRootViewModel {
        let repository = InMemoryMemoRepository()

        return AppRootViewModel(
            loadMemosUseCase: LoadMemosUseCase(repository: repository),
            createMemoUseCase: CreateMemoUseCase(repository: repository),
            saveMemoUseCase: SaveMemoUseCase(repository: repository),
            elementFactory: CanvasElementFactory()
        )
    }

    func reload() {
        memos = loadMemosUseCase.execute()
    }

    func createMemo() -> Memo {
        let memo = createMemoUseCase.execute()
        reload()
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
        selectedMemo = memo
        saveMemoUseCase.execute(memo)
        reload()
    }

    func saveMemo(_ memo: Memo) {
        selectedMemo = memo
        saveMemoUseCase.execute(memo)
        reload()
    }

    func updateAdjustment(_ adjustment: ImageAdjustment) {
        imageAdjustment = adjustment
    }

    func commitImageMemo() {
        addElement(using: .image)
        cutoutDraft = ImageCutoutDraft()
        imageAdjustment = .default
    }
}
