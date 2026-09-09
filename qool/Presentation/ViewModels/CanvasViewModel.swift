import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class CanvasViewModel: ObservableObject {
    /// マスクを起こすときに、表示の大きさへ掛ける倍率。
    /// 拡大しても縁が粗く見えないよう余裕を持たせます。
    static let maskScale: CGFloat = 3

    /// マスクを起こす画素数の上限（長辺）。
    static let maximumMaskLongSide: CGFloat = 1024

    /// マスクから輪郭を導くときに「内側」とみなす被覆率。
    static let maskContourThreshold: UInt8 = 128

    @Published private(set) var memo: Memo
    @Published var selectedTool: CanvasTool = .select
    @Published var selectedElementIDs: Set<CanvasElement.ID> = []
    @Published var editingUnionElementID: CanvasElement.ID?
    @Published var selectedUnionSourceID: CanvasElementSnapshot.ID?
    @Published var draftElement: CanvasElement?

    private var pathDraftPoints: [CGPoint] = []
    private let selectionService: CanvasSelectionService
    private let draftElementBuilder: CanvasDraftElementBuilder
    private let moveElementsUseCase: MoveCanvasElementsUseCase
    private let deleteElementsUseCase: DeleteCanvasElementsUseCase
    private let updateElementUseCase: UpdateCanvasElementUseCase
    private let unionElementsUseCase: UnionCanvasElementsUseCase
    private let reorderElementsUseCase: ReorderCanvasElementsUseCase
    private let resizeElementUseCase = ResizeCanvasElementUseCase()
    private let imageStore: CanvasImageStore
    private let maskStore: CutoutMaskStore
    private let maskRasterizer = CutoutMaskRasterizer()
    private let maskCodec = CutoutMaskPNGCodec()
    private let maskFilters = CutoutMaskFilters()
    private let maskContourDeriver: any MaskContourDeriverProtocol = MaskContourDeriverInfrastructure()
    private let regionMaskExtractor: any RegionMaskExtractorProtocol = RegionFillExtractorInfrastructure()
    private let importImageUseCase: ImportImageUseCase
    private let cropGeometry = CutoutCropGeometry()
    private let buildCutoutContourUseCase: BuildCutoutContourUseCase
    private let buildCutoutCandidatesUseCase: BuildCutoutCandidatesUseCase
    private let onSave: (Memo) -> Void

    init(
        memo: Memo,
        imageStore: CanvasImageStore,
        maskStore: CutoutMaskStore,
        importImageUseCase: ImportImageUseCase,
        buildCutoutContourUseCase: BuildCutoutContourUseCase = BuildCutoutContourUseCase(),
        buildCutoutCandidatesUseCase: BuildCutoutCandidatesUseCase = BuildCutoutCandidatesUseCase(),
        selectionService: CanvasSelectionService = CanvasSelectionService(),
        draftElementBuilder: CanvasDraftElementBuilder = CanvasDraftElementBuilder(),
        moveElementsUseCase: MoveCanvasElementsUseCase = MoveCanvasElementsUseCase(),
        deleteElementsUseCase: DeleteCanvasElementsUseCase = DeleteCanvasElementsUseCase(),
        updateElementUseCase: UpdateCanvasElementUseCase = UpdateCanvasElementUseCase(),
        unionElementsUseCase: UnionCanvasElementsUseCase = UnionCanvasElementsUseCase(),
        reorderElementsUseCase: ReorderCanvasElementsUseCase = ReorderCanvasElementsUseCase(),
        onSave: @escaping (Memo) -> Void
    ) {
        self.memo = memo
        self.selectionService = selectionService
        self.draftElementBuilder = draftElementBuilder
        self.moveElementsUseCase = moveElementsUseCase
        self.deleteElementsUseCase = deleteElementsUseCase
        self.updateElementUseCase = updateElementUseCase
        self.unionElementsUseCase = unionElementsUseCase
        self.reorderElementsUseCase = reorderElementsUseCase
        self.imageStore = imageStore
        self.maskStore = maskStore
        self.importImageUseCase = importImageUseCase
        self.buildCutoutContourUseCase = buildCutoutContourUseCase
        self.buildCutoutCandidatesUseCase = buildCutoutCandidatesUseCase
        self.onSave = onSave
    }

    /// 押した場所から色の近い範囲を広げたマスク。切り抜きシートの領域選択が使います。
    func regionMask(in image: NSImage, at point: CGPoint, tolerance: Int) -> CutoutMask? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        return regionMaskExtractor.regionMask(in: cgImage, at: point, tolerance: tolerance)
    }

    /// 要素が持つマスク。切り抜きシートが編集の土台にします。
    func cutoutMask(for element: CanvasElement) -> CutoutMask? {
        element.cutoutMask.flatMap { maskStore.mask(for: $0, in: memo.id) }
    }

    /// 描画に使うマスク。余白のぶん膨らませた形です。持っていなければ `nil`。
    func drawingMask(for element: CanvasElement) -> CutoutDrawingMask? {
        maskStore.drawingMask(for: element, in: memo.id)
    }

    /// 要素が参照している画像。まだ読めていなければ `nil`。
    ///
    /// `Memo` は値型で編集のたびにコピーされるため、画像の実体は
    /// [CanvasImageStore](../Support/CanvasImageStore.swift) が別に持ちます。
    func image(for element: CanvasElement) -> NSImage? {
        guard let assetID = element.imageAssetID else {
            return nil
        }

        return imageStore.image(for: assetID, in: memo.id)
    }

    /// なぞった点列から輪郭を作り、要素へ反映する。
    ///
    /// 点が足りず輪郭にならなければ `false` を返し、**要素は変えません。**
    /// 元画像と輪郭の両方を残すので、あとからなぞり直せます。
    @discardableResult
    func applyCutout(tracePoints: [CGPoint], to elementID: CanvasElement.ID) -> Bool {
        applyCutout(contours: buildCutoutContourUseCase(tracePoints: tracePoints), to: elementID)
    }

    /// 候補から選んだ輪郭を要素へ反映する。
    ///
    /// - Parameter mask: 抽出器が返したマスク。**あればこれを正として保存し、
    ///   輪郭からは焼き直しません。** 縁の半透明が残るのはこの経路だけです。
    @discardableResult
    func applyCutout(
        contours: [CanvasPathContour],
        mask: CutoutMask? = nil,
        to elementID: CanvasElement.ID
    ) -> Bool {
        // **マスクがあれば輪郭はそこから導きます。** 手直しはマスクに対して行うので、
        // 渡された輪郭は古いことがあります。正はマスクです。
        let resolved = mask.map(derivedContours(from:)) ?? contours

        guard !resolved.isEmpty else {
            return false
        }

        updateElementUseCase(in: &memo.canvas.elements, id: elementID) { element in
            element.pathContours = resolved
            element.isClosedPath = true
        }
        // **切り詰めで枠が変わるので、マスクの覆う範囲も同じだけ取り直します。**
        // 掛けないと切り詰め前の座標のまま解釈され、絵が縮んで見えます。
        let crop = cropSourceImage(of: elementID)
        let adjusted = crop.flatMap { crop in mask.flatMap { cropGeometry.applied(crop, to: $0) } } ?? mask

        storeCutoutMask(adjusted, of: elementID)
        save()

        return true
    }

    /// マスクから輪郭を導く。**フローティングメモの外形となぞり直しの土台に要ります。**
    private func derivedContours(from mask: CutoutMask) -> [CanvasPathContour] {
        maskContourDeriver
            .contours(from: mask, threshold: Self.maskContourThreshold)
            .map { points in
                CanvasPathContour(
                    points: points.map { NormalizedPoint(x: Double($0.x), y: Double($0.y)) },
                    isClosed: true
                )
            }
    }

    /// マスクを保存し、要素へ参照を持たせる。
    ///
    /// **抽出器がマスクを返していればそれを使います。** 輪郭から焼き直すと、
    /// 縁の半透明が 2 値に潰れて、マスクにした意味がなくなります。
    /// 手直しした場合など、マスクが無いときだけ輪郭から焼きます。
    private func storeCutoutMask(_ extracted: CutoutMask?, of elementID: CanvasElement.ID) {
        guard let element = memo.canvas.elements.first(where: { $0.id == elementID }) else {
            return
        }

        let size = maskPixelSize(for: element)
        let source = extracted.flatMap { maskFilters.resized($0, width: size.width, height: size.height) }

        guard let mask = (source ?? rasterizedMask(for: element, size: size))?.trimmed(),
              let data = maskCodec.encode(mask),
              let assetID = try? importImageUseCase(data, in: memo.id),
              let reference = CutoutMaskReference(assetID: assetID, extent: mask.extent) else {
            return
        }

        updateElementUseCase(in: &memo.canvas.elements, id: elementID) { element in
            element.cutoutMask = reference
        }
    }

    /// 輪郭から起こしたマスク。**抽出器のマスクが無いときの受け皿**です。
    ///
    /// **輪郭は残します。** なぞり直しの土台と、フローティングメモの外形に要ります。
    private func rasterizedMask(
        for element: CanvasElement,
        size: (width: Int, height: Int)
    ) -> CutoutMask? {
        guard !element.pathContours.isEmpty else {
            return nil
        }

        return maskRasterizer.mask(from: element.pathContours, width: size.width, height: size.height)
    }

    /// マスクを起こす画素数。**縦横の比は要素の枠に合わせます**（輪郭が枠を単位空間としているため）。
    ///
    /// **元画像ではなく表示の大きさで決めます。** 原寸の写真に合わせると、
    /// 320pt で表示するために 1600 画素四方のマスクを抱えることになり、
    /// 余白の計算だけで数秒かかりました（[#16](https://github.com/Greatnishioka/qool/issues/16)）。
    ///
    /// 元画像より細かくはしません。**画素を増やしても情報は増えません。**
    private func maskPixelSize(for element: CanvasElement) -> (width: Int, height: Int) {
        let frame = CGSize(
            width: max(1, element.frame.width),
            height: max(1, element.frame.height)
        )
        let frameLongSide = max(frame.width, frame.height)
        let source = image(for: element)?.cgImage(forProposedRect: nil, context: nil, hints: nil)

        var longSide = min(frameLongSide * Self.maskScale, Self.maximumMaskLongSide)

        if let source {
            longSide = min(longSide, CGFloat(max(source.width, source.height)))
        }

        let scale = longSide / frameLongSide

        return (
            width: max(1, Int((frame.width * scale).rounded())),
            height: max(1, Int((frame.height * scale).rounded()))
        )
    }

    /// 輪郭が決まった元画像を、そのまわりだけ残して置き換える。
    ///
    /// **見た目は変わりません。** 画像が小さくなるぶん枠も縮め、輪郭を取り直します。
    /// 置き換えられなくても静かに諦めます。原寸のままでも表示は正しいためです。
    @discardableResult
    private func cropSourceImage(of elementID: CanvasElement.ID) -> CutoutCrop? {
        guard let element = memo.canvas.elements.first(where: { $0.id == elementID }),
              let sourceImage = image(for: element)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let pixelSize = CGSize(width: sourceImage.width, height: sourceImage.height)

        guard let crop = cropGeometry.crop(
                  for: element.pathContours,
                  imagePixelSize: pixelSize,
                  displaySize: element.frame.size
              ),
              let cropped = sourceImage.cropping(to: crop.pixelRect),
              let data = CanvasImageStore.pngData(from: cropped),
              let assetID = try? importImageUseCase(data, in: memo.id) else {
            return nil
        }

        updateElementUseCase(in: &memo.canvas.elements, id: elementID) { element in
            element = cropGeometry.applied(crop, to: element, assetID: assetID)
        }

        return crop
    }

    /// なぞりから作った候補。推奨 → スコア降順 → 手描き の順で並びます。**要素は変えません。**
    ///
    /// 被写体マスクの抽出に Vision の推論が入るため非同期です。
    func cutoutCandidates(image: NSImage, tracePoints: [CGPoint]) async -> [CutoutCandidate] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        return await buildCutoutCandidatesUseCase(image: cgImage, tracePoints: tracePoints)
    }

    /// 切り抜きを解除し、元の矩形表示へ戻す。
    ///
    /// **切り詰める前の画像まで戻します。** 輪郭を消すだけでは、
    /// 適用時に切り詰めた「輪郭 + 余白」の絵が残り、元の写真へ戻れません。
    func clearCutout(of elementID: CanvasElement.ID) {
        updateElementUseCase(in: &memo.canvas.elements, id: elementID) { element in
            element = cropGeometry.restored(element)
            element.pathContours = []
            element.cutoutMask = nil
        }
        save()
    }

    /// ファイルから画像を取り込む。読めない形式なら `false`。
    @discardableResult
    func importImage(from url: URL, at point: CGPoint, canvasSize: CGSize) -> Bool {
        guard let image = NSImage(contentsOf: url) else {
            return false
        }

        return importImage(image, at: point, canvasSize: canvasSize)
    }

    @discardableResult
    func importImage(_ image: NSImage, at point: CGPoint, canvasSize: CGSize) -> Bool {
        guard let data = CanvasImageStore.pngData(from: image) else {
            return false
        }

        do {
            let assetID = try importImageUseCase(data, in: memo.id)
            let element = CanvasElement(
                kind: .imageCutout,
                frame: imageFrame(for: image.size, at: point, canvasSize: canvasSize),
                fillColor: .clear,
                showsStroke: false,
                imageAssetID: assetID
            )

            memo.canvas.elements.append(element)
            selectedTool = .select
            selectedElementIDs = [element.id]
            save()

            return true
        } catch {
            return false
        }
    }

    /// 長辺 320pt に収め、落とした位置を中心に置く。キャンバスからはみ出す分は寄せます。
    private func imageFrame(for imageSize: CGSize, at point: CGPoint, canvasSize: CGSize) -> CGRect {
        let maximumLength: CGFloat = 320
        let scale = min(1, maximumLength / max(1, max(imageSize.width, imageSize.height)))
        let size = CGSize(
            width: max(1, imageSize.width * scale),
            height: max(1, imageSize.height * scale)
        )

        return CGRect(
            origin: CGPoint(
                x: min(max(point.x - size.width / 2, 0), max(0, canvasSize.width - size.width)),
                y: min(max(point.y - size.height / 2, 0), max(0, canvasSize.height - size.height))
            ),
            size: size
        )
    }

    var selectedElement: CanvasElement? {
        selectionService.selectedElement(in: memo.canvas.elements, selectedIDs: selectedElementIDs)
    }
    
    var selectedElementID: CanvasElement.ID? {
        selectionService.selectedElementID(from: selectedElementIDs)
    }

    var selectedElementsCount: Int {
        selectedElementIDs.count
    }

    var hasSelection: Bool {
        !selectedElementIDs.isEmpty
    }

    var selectedElements: [CanvasElement] {
        selectionService.selectedElements(in: memo.canvas.elements, selectedIDs: selectedElementIDs)
    }

    var canUnionSelection: Bool {
        selectedElementIDs.count >= 2
    }

    var editingUnionSources: [CanvasElementSnapshot] {
        guard let editingUnionElementID,
              let element = memo.canvas.elements.first(where: { $0.id == editingUnionElementID }) else {
            return []
        }

        return element.unionSourceElements
    }

    var selectedUnionSource: CanvasElementSnapshot? {
        guard let selectedUnionSourceID else {
            return nil
        }

        return editingUnionSources.first { $0.id == selectedUnionSourceID }
    }

    func clearSelection() {
        selectedElementIDs.removeAll()
        editingUnionElementID = nil
        selectedUnionSourceID = nil
    }

    func selectTool(_ tool: CanvasTool) {
        if selectedTool == .path, tool != .path {
            clearPathDraft()
        }

        selectedTool = tool
        if tool != .select {
            clearSelection()
        }
    }

    func placePathPoint(at point: CGPoint, canvasSize: CGSize) {
        guard selectedTool == .path else {
            return
        }

        let point = clamped(point, in: canvasSize)

        // 3点以上ある場合かつ、最初の点の近くに点を置くと、パスを閉じる
        if pathDraftPoints.count >= 3,
           let firstPoint = pathDraftPoints.first,
           distance(from: point, to: firstPoint) <= 18 {
            commitPathDraft()
            return
        }

        pathDraftPoints.append(point)
        draftElement = draftElementBuilder.makePathElement(from: pathDraftPoints, isClosed: false)
    }

    func updateDraft(from start: CGPoint, to current: CGPoint, canvasSize: CGSize) {

        guard selectedTool != .select, selectedTool != .path else {
            return
        }

        let start = clamped(start, in: canvasSize)
        let current = clamped(current, in: canvasSize)
        draftElement = draftElementBuilder.makeElement(for: selectedTool, from: start, to: current)
    }

    func commitDraft(from start: CGPoint, to current: CGPoint, canvasSize: CGSize) {
        updateDraft(from: start, to: current, canvasSize: canvasSize)

        guard let draftElement, draftElementBuilder.isDrawable(draftElement) else {
            self.draftElement = nil
            return
        }

        memo.canvas.elements.append(draftElement)
        selectedTool = .select
        selectedElementIDs = [draftElement.id]
        self.draftElement = nil
        save()
    }

    func selectElement(id: CanvasElement.ID) {
        selectedTool = .select
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        selectedElementIDs = [id]
    }

    func toggleElementSelection(id: CanvasElement.ID) {
        selectedTool = .select
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        if selectedElementIDs.contains(id) {
            selectedElementIDs.remove(id)
        } else {
            selectedElementIDs.insert(id)
        }
    }

    func selectElements(in selectionFrame: CGRect) {
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        selectedElementIDs = selectionService.elementIDs(in: selectionFrame, elements: memo.canvas.elements)
    }

    func elementID(at point: CGPoint) -> CanvasElement.ID? {

        selectionService.elementID(at: point, in: memo.canvas.elements)
    }

    func unionSourceID(at point: CGPoint) -> CanvasElementSnapshot.ID? {
        editingUnionSources.reversed().first { source in
            source.frame.insetBy(dx: -6, dy: -6).contains(point)
        }?.id
    }

    
    func moveSelectedElement(by translation: CGSize, canvasSize: CGSize) {
        guard !selectedElementIDs.isEmpty else {
            return
        }

        let originalFrames = Dictionary(
            uniqueKeysWithValues: memo.canvas.elements
                .filter { selectedElementIDs.contains($0.id) }
                .map { ($0.id, $0.frame) }
        )

        moveElementsUseCase(
            in: &memo.canvas.elements,
            selectedIDs: selectedElementIDs,
            by: translation,
            canvasSize: canvasSize
        )

        for index in memo.canvas.elements.indices where selectedElementIDs.contains(memo.canvas.elements[index].id) {
            let element = memo.canvas.elements[index]
            guard !element.unionSourceElements.isEmpty,
                  let originalFrame = originalFrames[element.id] else {
                continue
            }

            let actualTranslation = CGSize(
                width: element.frame.minX - originalFrame.minX,
                height: element.frame.minY - originalFrame.minY
            )

            memo.canvas.elements[index].unionSourceElements = element.unionSourceElements.map { sourceElement in
                var sourceElement = sourceElement
                sourceElement.frame = sourceElement.frame.offsetBy(
                    dx: actualTranslation.width,
                    dy: actualTranslation.height
                )
                return sourceElement
            }
        }

        save()
    }

    // MARK: - 変形

    /// `point` にある角の掴み手。掴んでいなければ `nil`。
    ///
    /// **単一選択のときだけ返します。** 複数選んでいるときにどれか 1 つだけ変形すると、
    /// どの要素の角なのかが画面から読み取れません。
    func resizeCorner(at point: CGPoint) -> (elementID: CanvasElement.ID, corner: CanvasResizeCorner)? {
        guard let element = selectedElement,
              let corner = resizeElementUseCase.corner(at: point, of: element) else {
            return nil
        }

        return (element.id, corner)
    }

    /// 変形中の見た目。**確定前なので要素は変えません。**
    func resizedFrame(
        of elementID: CanvasElement.ID,
        corner: CanvasResizeCorner,
        to point: CGPoint,
        preservingAspectRatio: Bool = false
    ) -> CGRect? {
        guard let element = memo.canvas.elements.first(where: { $0.id == elementID }) else {
            return nil
        }

        return resizeElementUseCase(
            element,
            corner: corner,
            to: point,
            preservingAspectRatio: preservingAspectRatio
        )
    }

    func resizeElement(
        id elementID: CanvasElement.ID,
        corner: CanvasResizeCorner,
        to point: CGPoint,
        preservingAspectRatio: Bool = false
    ) {
        guard let frame = resizedFrame(
            of: elementID,
            corner: corner,
            to: point,
            preservingAspectRatio: preservingAspectRatio
        ) else {
            return
        }

        updateElementUseCase(in: &memo.canvas.elements, id: elementID) { element in
            element.frame = frame
        }
        save()
    }

    func updateFillColor(_ color: CanvasColor) {
        updateSelectedElement { element in
            element.fillColor = color
        }
    }

    func updateStrokeColor(_ color: CanvasColor) {
        updateSelectedElement { element in
            element.strokeColor = color
        }
    }

    func updateShowsStroke(_ showsStroke: Bool) {
        updateSelectedElement { element in
            element.showsStroke = showsStroke
            if showsStroke, element.strokeWidth == 0 {
                element.strokeWidth = 2
            }
        }
    }

    /// **太さ 0 でも枠線はオフにしません。** オフにすると設定 UI ごと畳まれ、
    /// スライダーを 0 まで下げた人が戻せなくなります。オンとオフはトグルだけが決めます。
    func updateStrokeWidth(_ strokeWidth: CGFloat) {
        updateSelectedElement { element in
            element.strokeWidth = strokeWidth
        }
    }

    func updateStrokeAlignment(_ alignment: CanvasStrokeAlignment) {
        updateSelectedElement { element in
            element.strokeAlignment = alignment
        }
    }

    func updateImageAdjustment(_ adjustment: ImageAdjustment) {
        updateSelectedElement { element in
            guard element.kind == .imageCutout else {
                return
            }

            element.imageAdjustment = adjustment
        }
    }

    func updateCornerRadius(_ cornerRadius: CGFloat) {
        updateSelectedElement { element in
            guard element.kind == .rectangle else {
                return
            }

            let maxRadius = max(0, min(element.frame.width, element.frame.height) / 2)
            element.cornerRadius = min(max(cornerRadius, 0), maxRadius)
        }
    }

    func updateText(_ text: String) {
        updateSelectedElement { element in
            element.text = text
        }
    }

    func deleteSelectedElement() {
        guard !selectedElementIDs.isEmpty else {
            return
        }

        deleteElementsUseCase(in: &memo.canvas.elements, selectedIDs: selectedElementIDs)
        selectedElementIDs.removeAll()
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        save()
    }

    /// 選んだ要素を重なり順の前後へ動かす。
    ///
    /// **`canvas.elements` の並びがそのまま重なり順です。** 別に順序を持つと、
    /// 描画と当たり判定のどちらが正なのかが分からなくなります。
    func reorderSelectedElements(to order: CanvasElementOrder) {
        guard canReorderSelection(to: order) else {
            return
        }

        reorderElementsUseCase(in: &memo.canvas.elements, selectedIDs: selectedElementIDs, to: order)
        save()
    }

    /// 端に着いていれば `false`。押しても何も起きないボタンを潰すために使います。
    func canReorderSelection(to order: CanvasElementOrder) -> Bool {
        reorderElementsUseCase.canReorder(memo.canvas.elements, selectedIDs: selectedElementIDs, to: order)
    }

    func unionSelectedElements() {
        guard canUnionSelection else {
            return
        }

        guard let unionElement = unionElementsUseCase(from: selectedElements) else {
            return
        }

        // ここでは掃除しません。**結合要素を足す前に走ると、元要素の画像を消します。**
        // 結合しても画像は `unionSourceElements` が参照し続けるので、孤児は生まれません。
        deleteElementsUseCase(in: &memo.canvas.elements, selectedIDs: selectedElementIDs)
        memo.canvas.elements.append(unionElement)
        selectedElementIDs = [unionElement.id]
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        save()
    }

    func separateSelectedElement() {
        guard let selectedElementID,
              let elementIndex = memo.canvas.elements.firstIndex(where: { $0.id == selectedElementID }) else {
            return
        }

        let sourceElements = memo.canvas.elements[elementIndex].unionSourceElements.map(\.element)
        guard !sourceElements.isEmpty else {
            return
        }

        memo.canvas.elements.remove(at: elementIndex)
        memo.canvas.elements.append(contentsOf: sourceElements)
        selectedElementIDs = Set(sourceElements.map(\.id))
        editingUnionElementID = nil
        selectedUnionSourceID = nil
        save()
    }

    func beginEditingUnionElement(at point: CGPoint) {
        guard selectedTool == .select,
              let elementID = elementID(at: point),
              let element = memo.canvas.elements.first(where: { $0.id == elementID }),
              !element.unionSourceElements.isEmpty else {
            return
        }

        editingUnionElementID = element.id
        selectedElementIDs = [element.id]
        selectedUnionSourceID = unionSourceID(at: point) ?? element.unionSourceElements.last?.id
    }

    func selectUnionSource(id: CanvasElementSnapshot.ID) {
        guard editingUnionSources.contains(where: { $0.id == id }) else {
            return
        }

        selectedUnionSourceID = id
    }

    func moveUnionSource(id: CanvasElementSnapshot.ID, by translation: CGSize, canvasSize: CGSize) {
        guard let editingUnionElementID,
              let elementIndex = memo.canvas.elements.firstIndex(where: { $0.id == editingUnionElementID }),
              let sourceIndex = memo.canvas.elements[elementIndex].unionSourceElements.firstIndex(where: { $0.id == id }) else {
            return
        }

        var sourceElements = memo.canvas.elements[elementIndex].unionSourceElements
        sourceElements[sourceIndex].frame = clamped(
            sourceElements[sourceIndex].frame.offsetBy(dx: translation.width, dy: translation.height),
            in: canvasSize
        )

        let currentUnionElement = memo.canvas.elements[elementIndex]
        guard let updatedUnionElement = unionElementsUseCase(
            from: sourceElements.map(\.element),
            id: currentUnionElement.id,
            styleSource: currentUnionElement
        ) else {
            return
        }

        memo.canvas.elements[elementIndex] = updatedUnionElement
        selectedElementIDs = [updatedUnionElement.id]
        selectedUnionSourceID = id
        save()
    }

    func updateSelectedUnionSourceCornerRadius(_ cornerRadius: CGFloat) {
        guard let selectedUnionSourceID else {
            return
        }

        updateUnionSource(id: selectedUnionSourceID) { sourceElement in
            guard sourceElement.kind == .rectangle else {
                return
            }

            let maxRadius = max(0, min(sourceElement.frame.width, sourceElement.frame.height) / 2)
            sourceElement.cornerRadius = min(max(cornerRadius, 0), maxRadius)
        }
    }

    private func updateSelectedElement(_ mutation: (inout CanvasElement) -> Void) {
        guard let selectedElementID else {
            return
        }

        updateElementUseCase(in: &memo.canvas.elements, id: selectedElementID, mutation)
        save()
    }

    private func updateUnionSource(
        id sourceID: CanvasElementSnapshot.ID,
        mutation: (inout CanvasElementSnapshot) -> Void
    ) {
        guard let editingUnionElementID,
              let elementIndex = memo.canvas.elements.firstIndex(where: { $0.id == editingUnionElementID }),
              let sourceIndex = memo.canvas.elements[elementIndex].unionSourceElements.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        var sourceElements = memo.canvas.elements[elementIndex].unionSourceElements
        mutation(&sourceElements[sourceIndex])

        let currentUnionElement = memo.canvas.elements[elementIndex]
        guard let updatedUnionElement = unionElementsUseCase(
            from: sourceElements.map(\.element),
            id: currentUnionElement.id,
            styleSource: currentUnionElement
        ) else {
            return
        }

        memo.canvas.elements[elementIndex] = updatedUnionElement
        selectedElementIDs = [updatedUnionElement.id]
        selectedUnionSourceID = sourceID
        save()
    }

    private func save() {
        onSave(memo)
    }

    private func commitPathDraft() {
        // パスが3点以下の場合はドラフトをクリアして終了する。
        guard let pathElement = draftElementBuilder.makePathElement(from: pathDraftPoints, isClosed: true),
              pathElement.pathPoints.count >= 3 else {
            clearPathDraft()
            return
        }

        memo.canvas.elements.append(pathElement)
        selectedTool = .select
        selectedElementIDs = [pathElement.id]
        clearPathDraft()
        save()
    }

    private func clearPathDraft() {
        pathDraftPoints = []
        draftElement = nil
    }

    private func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), size.width),
            y: min(max(point.y, 0), size.height)
        )
    }

    private func clamped(_ frame: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: min(max(frame.minX, 0), max(0, size.width - frame.width)),
            y: min(max(frame.minY, 0), max(0, size.height - frame.height)),
            width: frame.width,
            height: frame.height
        )
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
