import AppKit
import SwiftUI

/// S6 画像切り抜き。画像の外周をなぞって輪郭を決めるシートです。
///
/// **正確になぞる必要はありません。** なぞりは `ContourSmoother` が整えるための下地で、
/// トゲが取れ、直線は直線に寄り、角は残ります。
///
/// なぞって決めたあとは、ペン・消しゴム・投げ縄で手直しできます。
/// **手直しはラスターマスクを使わず、多角形の合成で行います**
/// （[方式の判断](../../../docs/image-editing/04-integration-plan.md)）。
struct ImageCutoutView: View {
    /// 前の点からこれ以下しか動いていない点は捨てる（正規化距離）。
    /// 間引かないと 1 回のドラッグで数千点になり、平滑化が重くなります。
    private static let minimumTraceSpacing: CGFloat = 0.006

    /// ブラシの太さ（表示ポイント）。正規化してから合成に渡します。
    private static let brushSizeRange: ClosedRange<CGFloat> = 4...80
    private static let defaultBrushSize: CGFloat = 24

    /// ブラシの縁の柔らかさ。半径に対する割合です。
    private static let brushSoftnessRange: ClosedRange<CGFloat> = 0...1
    private static let defaultBrushSoftness: CGFloat = 0.35

    /// 編集で使うマスクの画素数（長辺）。**保存時にはここから縮めます。**
    /// 粗すぎるとブラシの縁が階段になり、細かすぎると 1 手ごとの差分が重くなります。
    private static let editingMaskLongSide: CGFloat = 1024

    /// マスクを重ねて見せるときの濃さ。
    private static let maskOverlayOpacity: Double = 0.45

    /// 領域選択の許容差。**色の違いをどこまで同じ領域とみなすか。**
    private static let toleranceRange: ClosedRange<CGFloat> = 1...96
    private static let defaultTolerance: CGFloat = 24

    /// 表示倍率の範囲。1 が「画像全体が収まっている状態」です。
    private static let zoomRange: ClosedRange<CGFloat> = 1...12
    /// ホイールの 1 目盛あたりの倍率。**掛け算で効かせます。**
    /// 足し算にすると、拡大しているときほど 1 目盛が効かなくなります。
    private static let zoomPerScrollPoint: CGFloat = 0.004

    let image: NSImage
    let existingContours: [CanvasPathContour]
    /// 今のマスク。**手直しはこれを土台にします。**
    let existingMask: CutoutMask?
    let makeCandidates: (NSImage, [CGPoint]) async -> [CutoutCandidate]
    /// 押した場所から色の近い範囲を広げる。領域選択の道具が使います。
    let makeRegionMask: (NSImage, CGPoint, Int) -> CutoutMask?
    let onApply: ([CanvasPathContour], CutoutMask?) -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void
    /// 戻せる手数。設定で変えられます。
    let historyLimit: Int

    @State private var tracePoints: [CGPoint] = []
    /// 手で選んだ候補。未選択なら推奨を使います。
    @State private var selectedCandidateID: CutoutCandidate.ID?

    /// **なぞり終わりに一度だけ作ります。**
    /// 計算プロパティにすると `body` の評価ごとに走り、抽出器を足したときに
    /// 画像解析がメインスレッドで何度も動きます。
    @State private var candidates: [CutoutCandidate] = []
    /// 抽出中。Vision の推論が入るため、待ち時間が見えるようにします。
    @State private var isExtracting = false

    @State private var tool: CutoutSheetTool = .trace
    @State private var brushSize = ImageCutoutView.defaultBrushSize
    /// 手直し中のなぞり。指を離した時点でまとめて合成します。
    @State private var strokePoints: [CGPoint] = []
    /// **`nil` は「まだ手直ししていない」を表します。** 手直しを始めた時点で、
    /// そのときのマスクを土台にして積み始めます。
    @State private var history: CutoutMaskEditHistory?
    /// 手直しの土台。なぞり直すか候補を選び直すと入れ替わります。
    @State private var baseMask: CutoutMask?
    /// 重ねて見せるための画像。**`body` で作ると毎フレーム変換が走ります。**
    @State private var previewImage: CGImage?
    @State private var brushSoftness = ImageCutoutView.defaultBrushSoftness
    @State private var tolerance = ImageCutoutView.defaultTolerance

    /// 表示倍率と、拡大したときの表示位置のずらし量。
    /// **画像を収めた矩形を基準にしています**（`imageRect`）。
    @State private var zoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    /// ピンチの最中は、始めたときの倍率からの相対で効かせます。
    @State private var pinchBaseScale: CGFloat = 1
    /// スペースを押している間は、ドラッグがなぞりではなく移動になります。
    @State private var isSpacePressed = false
    /// 移動中のドラッグで、前回までに動かした量。差分だけ足すために持ちます。
    @State private var lastPanTranslation: CGSize = .zero

    private let editMask = EditCutoutMaskUseCase()
    private let maskStamp = CutoutMaskStamp()
    private let maskFilters = CutoutMaskFilters()
    private let maskRasterizer = CutoutMaskRasterizer()
    private let maskCodec = CutoutMaskPNGCodec()

    private var selectedCandidate: CutoutCandidate? {
        if let selectedCandidateID, let picked = candidates.first(where: { $0.id == selectedCandidateID }) {
            return picked
        }

        return candidates.first { $0.isRecommended } ?? candidates.first
    }

    /// 今見えているマスク。**これが切り抜きの正です。**
    private var previewMask: CutoutMask? {
        history?.current ?? baseMask
    }

    /// 適用する輪郭。**マスクがあれば呼び出し側が導き直す**ので、ここでは表示用の値を渡します。
    private var previewContours: [CanvasPathContour] {
        tracePoints.isEmpty ? existingContours : (selectedCandidate?.contours ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            toolBar

            Divider()

            preview

            if !candidates.isEmpty {
                Divider()
                candidateBar
            }

            Divider()

            footer
        }
        .frame(width: 860, height: 640)
        .onAppear { rebuildBaseMask() }
    }

    private var header: some View {
        HStack {
            Text("画像を切り抜く")
                .font(.system(size: 13, weight: .bold))

            Spacer()

            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var hint: String {
        if tracePoints.isEmpty {
            return existingContours.isEmpty
                ? "画像の上をドラッグして、切り抜きたい範囲を囲みます"
                : "現在の輪郭を表示しています。ドラッグでなぞり直せます"
        }

        if isExtracting {
            return "被写体を探しています…"
        }

        return candidates.isEmpty
            ? "指を離すと候補を作ります"
            : "候補を選び直せます。やり直すには「なぞり直す」"
    }

    private var toolBar: some View {
        HStack(spacing: 12) {
            Picker("道具", selection: $tool) {
                ForEach(CutoutSheetTool.allCases) { candidate in
                    Label(candidate.displayName, systemImage: candidate.systemImage).tag(candidate)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            if tool.usesBrushSize {
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Slider(value: $brushSize, in: Self.brushSizeRange)
                        .frame(width: 90)
                    Text("\(Int(brushSize))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }

                // 縁の柔らかさ。**マスクにしたことで持てるようになった値**です。
                HStack(spacing: 6) {
                    Image(systemName: "drop")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Slider(value: $brushSoftness, in: Self.brushSoftnessRange)
                        .frame(width: 90)
                    Text("\(Int(brushSoftness * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                .help("ブラシの縁の柔らかさ")
            }

            if tool.fillsRegion {
                HStack(spacing: 6) {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Slider(value: $tolerance, in: Self.toleranceRange)
                        .frame(width: 110)
                    Text("\(Int(tolerance))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
                .help("同じ領域とみなす色の違い")
            }

            Spacer()

            // 押すと等倍へ戻ります。**移動の手段が拡大の中心しかないため、
            // 迷子になったときに戻れる出口を用意しています。**
            Button {
                resetZoom()
            } label: {
                Text("\(Int(zoomScale * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 44)
            }
            .buttonStyle(.bordered)
            .disabled(zoomScale == 1)
            .keyboardShortcut("1", modifiers: .shift)
            .help("全体を表示（⇧1）")

            Button {
                history?.undo()
                refreshPreviewImage()
            } label: {
                Label("元に戻す", systemImage: "arrow.uturn.backward")
            }
            .disabled(history?.canUndo != true)

            Button {
                history?.redo()
                refreshPreviewImage()
            } label: {
                Label("やり直す", systemImage: "arrow.uturn.forward")
            }
            .disabled(history?.canRedo != true)
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var preview: some View {
        GeometryReader { proxy in
            let rect = imageRect(in: proxy.size)

            ZStack(alignment: .topLeading) {
                Color(nsColor: .windowBackgroundColor)

                Image(nsImage: image)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                // なぞり中は画像を少し落として、線を見やすくします。
                if !tracePoints.isEmpty {
                    Color.black.opacity(0.06)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                maskOverlay(in: rect)
                traceOverlay(in: rect)

                // どちらもクリックを奪わないので、なぞりと同時に効きます。
                ScrollWheelReader { input in
                    handleScroll(input, in: proxy.size)
                }
                SpaceKeyReader { isSpacePressed = $0 }
            }
            // **拡大した画像はこの枠からはみ出します。** 切らないと、
            // 後ろに置かれたぶんツールバーの上に描かれて隠します。
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let anchor = CGPoint(
                            x: value.startLocation.x,
                            y: value.startLocation.y
                        )
                        setZoom(pinchBaseScale * value.magnification, anchor: anchor, in: proxy.size)
                    }
                    .onEnded { _ in pinchBaseScale = zoomScale }
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if isSpacePressed {
                            panByDrag(value.translation, in: proxy.size)
                        } else if tool.fillsRegion {
                            // 領域は指を離した時点で 1 回だけ広げます。
                        } else if tool == .trace {
                            appendTracePoint(value.location, in: rect)
                        } else {
                            appendStrokePoint(value.location, in: rect)
                        }
                    }
                    .onEnded { value in
                        pinchBaseScale = zoomScale

                        guard !isSpacePressed else {
                            lastPanTranslation = .zero
                            return
                        }

                        if tool.fillsRegion {
                            fillRegion(at: value.location, in: rect)
                        } else if tool == .trace {
                            // なぞり終わりにまとめて抽出します。
                            selectedCandidateID = nil
                            extract()
                        } else {
                            applyStroke(in: rect)
                        }
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isSpacePressed) { _, isPressed in
            // 掴めることが見て分かるようにします。
            if isPressed {
                NSCursor.openHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    /// 今のマスクを色で重ねて見せる。
    ///
    /// **破線ではなく塗りで見せます。** ブラシの柔らかさや縁の半透明は、
    /// 線で表せません。マスクにした意味が画面に出ないと調整のしようがありません。
    @ViewBuilder
    private func maskOverlay(in rect: CGRect) -> some View {
        if let previewImage {
            Color.accentColor
                .opacity(Self.maskOverlayOpacity)
                .mask {
                    Image(decorative: previewImage, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        // 明るさを不透明度として読み替えます。
                        .luminanceToAlpha()
                }
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func traceOverlay(in rect: CGRect) -> some View {
        if tracePoints.count >= 2 {
            tracePath(in: rect)
                .stroke(Color.accentColor.opacity(0.45), lineWidth: 1.5)
                .allowsHitTesting(false)
        }

        if strokePoints.count >= 2 {
            // 足すか引くかで色を変えます。押している間、どちらの操作かが分かるようにします。
            strokePath(in: rect)
                .stroke(
                    (tool.editMode == .subtract ? Color.red : Color.green).opacity(0.55),
                    style: StrokeStyle(
                        lineWidth: tool.usesBrushSize ? brushSize : 1.5,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .allowsHitTesting(false)
        }
    }

    /// 候補選択バー。抽出器が増えるとここに並びます。
    private var candidateBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(candidates) { candidate in
                    let isSelected = selectedCandidate?.id == candidate.id

                    Button {
                        selectedCandidateID = candidate.id
                        rebuildBaseMask()
                    } label: {
                        HStack(spacing: 5) {
                            if candidate.isRecommended {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                            }

                            Text(candidate.displayName)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))

                            if let score = candidate.score {
                                Text(String(format: "%.1f", score))
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .tertiarySystemFill))
                        )
                    }
                    .buttonStyle(.plain)
                    .help(candidate.helpText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("キャンセル", action: onDismiss)

            if !existingContours.isEmpty, tracePoints.isEmpty {
                Button("切り抜きを解除") {
                    onClear()
                    onDismiss()
                }
            }

            Spacer()

            Button("やり直す") {
                resetZoom()
                tracePoints = []
                selectedCandidateID = nil
                candidates = []
                tool = .trace
                // 土台が変わるので手直しも捨てます。積んだままだと古い形へ戻せてしまいます。
                rebuildBaseMask()
            }
            .disabled(tracePoints.isEmpty && history == nil)

            // 手直しした形をそのまま渡します。**候補を渡すと手直しが捨てられます。**
            Button("適用") {
                onApply(previewContours, previewMask)
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(previewMask == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func extract() {
        let points = tracePoints
        isExtracting = true

        Task {
            let extracted = await makeCandidates(image, points)
            // なぞり直された後の結果は捨てます。
            guard points == tracePoints else {
                return
            }

            candidates = extracted
            isExtracting = false
            rebuildBaseMask()
        }
    }

    // MARK: - 手直し

    /// 手直しのなぞりは画像の外も拾います。**輪郭の外から入ってくる操作を切らない**ためです。
    /// はみ出した分は合成時に落ちます。
    private func appendStrokePoint(_ location: CGPoint, in rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else {
            return
        }

        let point = CGPoint(
            x: (location.x - rect.minX) / rect.width,
            y: (location.y - rect.minY) / rect.height
        )

        if let lastPoint = strokePoints.last,
           hypot(point.x - lastPoint.x, point.y - lastPoint.y) <= Self.minimumTraceSpacing {
            return
        }

        strokePoints.append(point)
    }

    /// 指を離した時点で 1 回だけ合成します。
    ///
    /// **ドラッグ中は合成しません。** 画素をなめる処理なので、
    /// 毎フレーム走らせると指に追従しなくなります。
    private func applyStroke(in rect: CGRect) {
        let stroke = strokePoints
        strokePoints = []

        guard let mode = tool.editMode, !stroke.isEmpty, rect.width > 0,
              let base = editingBase() else {
            return
        }

        guard let stamp = maskStamp.stamp(
            points: stroke,
            radius: brushSize / 2 / rect.width,
            softness: tool.usesBrushSize ? brushSoftness : 0,
            width: base.current.width,
            height: base.current.height,
            // 投げ縄は囲んだ内側を塗ります。
            isClosed: tool.enclosesArea
        ) else {
            return
        }

        var editing = base
        editing.record(editMask(editing.current, combining: stamp, mode: mode))
        history = editing
        refreshPreviewImage()
    }

    /// 押した場所から領域を広げて合成する。
    ///
    /// **1 回のクリックで効きます。** 囲まれた場所（カップの取っ手の内側など）を
    /// 形どおりに一度で選べるのがブラシとの違いです。
    private func fillRegion(at location: CGPoint, in rect: CGRect) {
        guard let mode = tool.editMode, rect.width > 0, rect.height > 0,
              let base = editingBase() else {
            return
        }

        let point = CGPoint(
            x: (location.x - rect.minX) / rect.width,
            y: (location.y - rect.minY) / rect.height
        )

        guard (0..<1).contains(point.x), (0..<1).contains(point.y),
              let region = makeRegionMask(image, point, Int(tolerance)),
              let placed = maskFilters.placedInUnitSpace(
                  region,
                  width: base.current.width,
                  height: base.current.height
              ) else {
            return
        }

        var editing = base
        editing.record(editMask(editing.current, combining: placed, mode: mode))
        history = editing
        refreshPreviewImage()
    }

    /// 手直しの土台。**始めた時点のマスクを単位空間へ載せ直してから積みます。**
    /// 切り詰めた範囲のままだと、なぞりが形の外へ出るたびに格子が変わります。
    private func editingBase() -> CutoutMaskEditHistory? {
        if let history {
            return history
        }

        guard let mask = baseMask else {
            return nil
        }

        return CutoutMaskEditHistory(mask, limit: historyLimit)
    }

    /// 土台を作り直す。なぞり直し・候補の選び直し・シートを開いた直後に呼びます。
    private func rebuildBaseMask() {
        let size = editingMaskSize()
        let source = selectedCandidate?.mask
            ?? existingMask
            ?? maskRasterizer.mask(
                from: previewContours,
                width: size.width,
                height: size.height
            )

        baseMask = source.flatMap {
            maskFilters.placedInUnitSpace($0, width: size.width, height: size.height)
        }
        history = nil
        refreshPreviewImage()
    }

    /// 編集で使う画素数。**縦横の比は画像に合わせます**（輪郭が画像の枠を単位空間としているため）。
    private func editingMaskSize() -> (width: Int, height: Int) {
        let imageSize = image.size
        let longSide = max(imageSize.width, imageSize.height)

        guard longSide > 0 else {
            return (width: 1, height: 1)
        }

        let scale = Self.editingMaskLongSide / longSide

        return (
            width: max(1, Int((imageSize.width * scale).rounded())),
            height: max(1, Int((imageSize.height * scale).rounded()))
        )
    }

    private func refreshPreviewImage() {
        previewImage = previewMask.flatMap { maskCodec.grayscaleImage(from: $0) }
    }

    // MARK: - 座標

    /// 画像を描いている矩形。なぞりの正規化もここを基準にします。
    ///
    /// **拡大縮小はこの 1 箇所で効かせます。** 表示も入力もすべてこの矩形を通るので、
    /// ここに倍率を入れれば、なぞりの正規化や輪郭の描画が自動で追随します。
    private func imageRect(in size: CGSize) -> CGRect {
        let fitted = fittedRect(in: size)
        guard zoomScale != 1 || zoomOffset != .zero else {
            return fitted
        }

        let zoomedSize = CGSize(width: fitted.width * zoomScale, height: fitted.height * zoomScale)

        return CGRect(
            x: fitted.midX - zoomedSize.width / 2 + zoomOffset.width,
            y: fitted.midY - zoomedSize.height / 2 + zoomOffset.height,
            width: zoomedSize.width,
            height: zoomedSize.height
        )
    }

    /// 画像を aspect-fit で収めた矩形。倍率 1 のときの位置と大きさです。
    private func fittedRect(in size: CGSize) -> CGRect {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }

        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        return CGRect(
            x: (size.width - fittedSize.width) / 2,
            y: (size.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    // MARK: - 拡大縮小

    /// `anchor` の下にある画像上の点を動かさずに倍率を変える。
    ///
    /// **これが移動も兼ねます。** 拡大したい場所へポインタを置いて操作すれば、
    /// そこへ寄っていくため、別に手のひらツールを持たなくて済みます。
    private func setZoom(_ scale: CGFloat, anchor: CGPoint, in size: CGSize) {
        let clamped = min(max(scale, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let current = imageRect(in: size)

        guard current.width > 0, current.height > 0 else {
            return
        }

        // 倍率 1 に戻ったら中央へ戻します。端に寄ったまま戻ると迷子になります。
        guard clamped > Self.zoomRange.lowerBound else {
            zoomScale = 1
            zoomOffset = .zero
            return
        }

        let unit = CGPoint(
            x: (anchor.x - current.minX) / current.width,
            y: (anchor.y - current.minY) / current.height
        )
        let fitted = fittedRect(in: size)

        zoomScale = clamped
        zoomOffset = clampedOffset(
            CGSize(
                width: anchor.x - fitted.midX + fitted.width * clamped * (0.5 - unit.x),
                height: anchor.y - fitted.midY + fitted.height * clamped * (0.5 - unit.y)
            ),
            scale: clamped,
            in: size
        )
    }

    /// スクロール 1 回分。**入力の種類で役割を分けます。**
    ///
    /// Figma と同じ割り当てです。ホイールは移動、⌘ を足すと拡大縮小、
    /// トラックパッドの 2 本指は移動、⇧ を足すと左右移動になります。
    private func handleScroll(_ input: ScrollWheelInput, in size: CGSize) {
        guard !input.wantsZoom else {
            setZoom(zoomScale * (1 + input.deltaY * Self.zoomPerScrollPoint), anchor: input.location, in: size)
            return
        }

        // ⇧ + ホイールは左右移動。横の値を持つ入力（トラックパッド）はそのまま使います。
        let translation = input.wantsHorizontal && input.deltaX == 0
            ? CGSize(width: input.deltaY, height: 0)
            : CGSize(width: input.deltaX, height: input.deltaY)

        panBy(translation, in: size)
    }

    /// スペースを押しながらのドラッグ。**差分だけを足します。**
    /// `translation` はドラッグ開始からの累計なので、そのまま足すと加速します。
    private func panByDrag(_ translation: CGSize, in size: CGSize) {
        panBy(
            CGSize(
                width: translation.width - lastPanTranslation.width,
                height: translation.height - lastPanTranslation.height
            ),
            in: size
        )
        lastPanTranslation = translation
    }

    private func panBy(_ translation: CGSize, in size: CGSize) {
        zoomOffset = clampedOffset(
            CGSize(
                width: zoomOffset.width + translation.width,
                height: zoomOffset.height + translation.height
            ),
            scale: zoomScale,
            in: size
        )
    }

    /// 画像の外側が見えないところまでずらし量を抑える。
    ///
    /// **拡大していない方向へは動かしません。** 等倍のときに動かせると、
    /// 画像を画面の外へ追い出せてしまいます。
    private func clampedOffset(_ offset: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let fitted = fittedRect(in: size)
        let limit = CGSize(
            width: fitted.width * (scale - 1) / 2,
            height: fitted.height * (scale - 1) / 2
        )

        return CGSize(
            width: min(max(offset.width, -limit.width), limit.width),
            height: min(max(offset.height, -limit.height), limit.height)
        )
    }

    private func resetZoom() {
        zoomScale = 1
        zoomOffset = .zero
        pinchBaseScale = 1
        lastPanTranslation = .zero
    }

    /// 画像の外はなぞりに含めません。輪郭が画像からはみ出すと、マスクが破綻します。
    private func appendTracePoint(_ location: CGPoint, in rect: CGRect) {
        guard rect.contains(location), rect.width > 0, rect.height > 0 else {
            return
        }

        let point = CGPoint(
            x: (location.x - rect.minX) / rect.width,
            y: (location.y - rect.minY) / rect.height
        )

        if let lastPoint = tracePoints.last,
           hypot(point.x - lastPoint.x, point.y - lastPoint.y) <= Self.minimumTraceSpacing {
            return
        }

        tracePoints.append(point)
    }

    private func path(for contours: [CanvasPathContour], in rect: CGRect) -> Path {
        var path = Path()

        for contour in contours where contour.points.count >= 2 {
            let points = contour.points.map { point in
                CGPoint(x: rect.minX + rect.width * point.x, y: rect.minY + rect.height * point.y)
            }

            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }

        return path
    }

    private func tracePath(in rect: CGRect) -> Path {
        polyline(tracePoints, in: rect)
    }

    private func strokePath(in rect: CGRect) -> Path {
        polyline(strokePoints, in: rect)
    }

    private func polyline(_ normalizedPoints: [CGPoint], in rect: CGRect) -> Path {
        var path = Path()
        let points = normalizedPoints.map { point in
            CGPoint(x: rect.minX + rect.width * point.x, y: rect.minY + rect.height * point.y)
        }

        guard let first = points.first else {
            return path
        }

        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        return path
    }
}
