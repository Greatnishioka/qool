import CoreGraphics
import Foundation
import Testing
@testable import qool

/// デスクトップに貼るメモ（第 3 段階 7）の検証。
struct FloatingMemoTests {
    private let buildOutline = BuildFloatingMemoOutlineUseCase()

    private func rectangle(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CanvasElement {
        CanvasElement(
            kind: .rectangle,
            frame: CGRect(x: x, y: y, width: width, height: height),
            fillColor: .paper
        )
    }

    // MARK: - 外形

    @Test func 要素のないキャンバスには形がない() {
        #expect(buildOutline(from: Canvas()) == nil)
    }

    @Test func 矩形1つの外形はその矩形になる() throws {
        let outline = try #require(buildOutline(from: Canvas(elements: [rectangle(20, 30, 100, 60)])))

        #expect(outline.bounds == CGRect(x: 20, y: 30, width: 100, height: 60))
        #expect(outline.contours.count == 1)

        // 単位空間の四隅だけが残ります。
        let xs = Set(outline.contours[0].points.map(\.x))
        let ys = Set(outline.contours[0].points.map(\.y))
        #expect(xs == [0, 1])
        #expect(ys == [0, 1])
    }

    @Test func 離れた2つの要素は外接矩形にまとめて2本の輪郭になる() throws {
        let canvas = Canvas(elements: [rectangle(0, 0, 50, 50), rectangle(150, 100, 50, 50)])
        let outline = try #require(buildOutline(from: canvas))

        #expect(outline.bounds == CGRect(x: 0, y: 0, width: 200, height: 150))
        #expect(outline.contours.count == 2)
    }

    @Test func 重なった2つの要素は1本の輪郭に合成される() throws {
        let canvas = Canvas(elements: [rectangle(0, 0, 100, 100), rectangle(50, 50, 100, 100)])
        let outline = try #require(buildOutline(from: canvas))

        #expect(outline.bounds == CGRect(x: 0, y: 0, width: 150, height: 150))
        #expect(outline.contours.count == 1)
        // L 字になるので、四角形より頂点が増えます。
        #expect(outline.contours[0].points.count > 4)
    }

    /// 描画は `rotationEffect` で回すので、外形も同じだけ回さないと形が合いません。
    /// **斜めの線がマスクから外れて切れます。**
    @Test func 回転した要素の外形も回る() throws {
        let line = CanvasElement(
            kind: .line,
            frame: CGRect(x: 0, y: 45, width: 100, height: 10),
            fillColor: .clear,
            rotationAngleDegrees: 90
        )
        let outline = try #require(buildOutline(from: Canvas(elements: [line])))

        // 横長の枠を 90 度回すと縦長になります。
        #expect(abs(outline.bounds.width - 10) < 0.0001)
        #expect(abs(outline.bounds.height - 100) < 0.0001)
        #expect(abs(outline.bounds.midX - 50) < 0.0001)
        #expect(abs(outline.bounds.midY - 50) < 0.0001)
    }

    /// 線やテキストは塗る面を持ちませんが、**掴めないと困る**ので frame で代用します。
    @Test func 面を持たない要素もframeの矩形として形になる() throws {
        let line = CanvasElement(
            kind: .line,
            frame: CGRect(x: 10, y: 10, width: 80, height: 40),
            fillColor: .clear
        )
        let outline = try #require(buildOutline(from: Canvas(elements: [line])))

        #expect(outline.bounds == CGRect(x: 10, y: 10, width: 80, height: 40))
    }

    // MARK: - ウィンドウの大きさ

    /// **紙は余白とぼかしを含まない形に敷きます。**
    /// 広げた形に敷くと、ぼけた縁まで白で塗り潰されて硬い縁に戻ります。
    @Test func 紙の形は余白のぶん輪郭より内側になる() throws {
        let contour = CanvasPathContour(points: (0..<24).map { index in
            let angle = Double(index) / 24 * 2 * .pi

            return NormalizedPoint(x: 0.5 + cos(angle) * 0.3, y: 0.5 + sin(angle) * 0.3)
        })
        let element = CanvasElement(
            kind: .imageCutout,
            frame: CGRect(x: 0, y: 0, width: 200, height: 200),
            fillColor: .clear,
            showsStroke: false,
            pathContours: [contour],
            imageAssetID: UUID(),
            imageAdjustment: ImageAdjustment(padding: 20, blur: 10, blurDirection: .outward)
        )

        let outline = try #require(buildOutline(from: Canvas(elements: [element])))

        let contourWidth = width(of: try #require(outline.contours.first))
        let paperWidth = width(of: try #require(outline.paperContours.first))

        #expect(paperWidth < contourWidth)
    }

    /// 余白もぼかしも無ければ、紙の形は輪郭と変わりません。
    @Test func 余白がなければ紙の形は輪郭と同じ() throws {
        let outline = try #require(buildOutline(from: Canvas(elements: [rectangle(0, 0, 100, 100)])))

        #expect(outline.paperContours == outline.contours)
    }

    private func width(of contour: CanvasPathContour) -> Double {
        let xs = contour.points.map(\.x)

        return (xs.max() ?? 0) - (xs.min() ?? 0)
    }

    @Test func ウィンドウは縦横比を保ったまま上限に収まる() {
        let size = FloatingMemoWindowManager.windowSize(for: CGRect(x: 0, y: 0, width: 1600, height: 800))

        #expect(size.width <= 360)
        #expect(size.height <= 480)
        #expect(abs(size.width / size.height - 2) < 0.0001)
    }

    @Test func 縦長でも高さの上限で決まり縦横比は崩れない() {
        let size = FloatingMemoWindowManager.windowSize(for: CGRect(x: 0, y: 0, width: 200, height: 2000))

        #expect(size.height <= 480)
        #expect(abs(size.width / size.height - 0.1) < 0.0001)
    }

    @Test func 小さすぎるメモは掴めるように広がる() {
        let size = FloatingMemoWindowManager.windowSize(for: CGRect(x: 0, y: 0, width: 20, height: 10))

        #expect(size.width >= 120)
        #expect(abs(size.width / size.height - 2) < 0.0001)
    }

    // MARK: - ヒットテスト

    private func unitContour(_ points: [(Double, Double)]) -> CanvasPathContour {
        CanvasPathContour(points: points.map { NormalizedPoint(x: $0.0, y: $0.1) })
    }

    private let viewBounds = CGRect(x: 0, y: 0, width: 100, height: 100)

    /// 左半分だけを覆う輪郭。
    private var leftHalf: [CanvasPathContour] {
        [unitContour([(0, 0), (0.5, 0), (0.5, 1), (0, 1)])]
    }

    @Test func 輪郭の内側はクリックを受ける() {
        let hitTest = ContourHitTest()

        #expect(hitTest.contains(CGPoint(x: 25, y: 50), in: leftHalf, bounds: viewBounds, isTopLeftOrigin: true))
        #expect(!hitTest.contains(CGPoint(x: 75, y: 50), in: leftHalf, bounds: viewBounds, isTopLeftOrigin: true))
    }

    /// 輪郭は左上原点なので、AppKit の既定（左下原点）では y を反転しないと上下が入れ替わります。
    @Test func 左下原点では上下が反転して判定される() {
        let hitTest = ContourHitTest()
        let topHalf = [unitContour([(0, 0), (1, 0), (1, 0.5), (0, 0.5)])]
        let nearTop = CGPoint(x: 50, y: 90)

        #expect(!hitTest.contains(nearTop, in: topHalf, bounds: viewBounds, isTopLeftOrigin: true))
        #expect(hitTest.contains(nearTop, in: topHalf, bounds: viewBounds, isTopLeftOrigin: false))
    }

    /// 描画が `eoFill` なので、穴の中は見た目どおり素通しになります。
    @Test func 穴の中はクリックを素通しする() {
        let hitTest = ContourHitTest()
        let ring = [
            unitContour([(0, 0), (1, 0), (1, 1), (0, 1)]),
            unitContour([(0.4, 0.4), (0.6, 0.4), (0.6, 0.6), (0.4, 0.6)])
        ]

        #expect(hitTest.contains(CGPoint(x: 10, y: 10), in: ring, bounds: viewBounds, isTopLeftOrigin: true))
        #expect(!hitTest.contains(CGPoint(x: 50, y: 50), in: ring, bounds: viewBounds, isTopLeftOrigin: true))
    }

    @Test func 輪郭の外の点は範囲外として弾く() {
        let hitTest = ContourHitTest()

        #expect(!hitTest.contains(CGPoint(x: -1, y: 50), in: leftHalf, bounds: viewBounds, isTopLeftOrigin: true))
        #expect(!hitTest.contains(CGPoint(x: 25, y: 50), in: [], bounds: viewBounds, isTopLeftOrigin: true))
    }

    // MARK: - 一覧とキャンバスの同期

    /// **キャンバスの保存が付箋を巻き戻さないこと。**
    ///
    /// 以前は 1 つの `Memo` が設計図と机の上の 1 枚を兼ねていたため、
    /// キャンバスが開いた時点の写しを書き戻すと、あいだの変更が消えました
    /// （[#27](https://github.com/Greatnishioka/qool/issues/27)）。
    /// **雛形と付箋を別のレコードに分けたので、構造的に起きません。**
    @MainActor
    @Test func キャンバスの保存で付箋の本文が巻き戻らない() async throws {
        let viewModel = AppRootViewModel.bootstrap(repository: InMemoryMemoRepositoryInfrastructure())
        let created = try #require(await viewModel.createMemo())

        // **雛形にテキスト要素が要ります。** 無い要素の本文は掃除で捨てられます。
        let element = CanvasElement(
            kind: .text,
            frame: CGRect(x: 0, y: 0, width: 100, height: 40),
            fillColor: .clear
        )
        var template = created
        template.canvas.elements = [element]
        await viewModel.saveMemo(template)
        template = try #require(viewModel.memos.first { $0.id == created.id })

        let note = try #require(await viewModel.createStickyNote(from: template, at: .zero))

        // 付箋の本文を書き換える。
        var written = note
        written.texts[element.id] = "付箋に書いた"
        await viewModel.saveStickyNote(written)

        // キャンバスは開いた時点の写しを書き戻す。
        var edited = template
        edited.title = "編集した"
        await viewModel.saveMemo(edited)

        let savedNote = try #require(viewModel.stickyNotes.first { $0.id == note.id })
        let savedTemplate = try #require(viewModel.memos.first { $0.id == created.id })

        #expect(savedNote.texts[element.id] == "付箋に書いた")
        #expect(savedTemplate.title == "編集した")
    }

    // MARK: - 永続化

    /// **貼り付け位置は `Memo` から外しました。** 位置は付箋が持ちます。
    /// 古い保存に残っていても読み飛ばせることの確認です。
    @Test func 貼り付け位置の残った古い雛形も読み込める() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "title": "古いメモ",
            "updatedAt": 0,
            "canvas": { "elements": [] },
            "floatingOrigin": { "x": 120, "y": 340 }
        }
        """
        let decoded = try JSONDecoder().decode(Memo.self, from: Data(json.utf8))

        #expect(decoded.title == "古いメモ")
    }
}
