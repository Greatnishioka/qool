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

    // MARK: - 永続化

    @Test func 貼った位置は保存して読み戻せる() throws {
        let memo = Memo(title: "貼ったメモ", floatingOrigin: CGPoint(x: 120, y: 340))
        let data = try JSONEncoder().encode(memo)
        let decoded = try JSONDecoder().decode(Memo.self, from: data)

        #expect(decoded.floatingOrigin == CGPoint(x: 120, y: 340))
    }

    /// 位置を持たない既存のメモを壊さないことの確認。
    @Test func 位置のない古いメモも読み込める() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "title": "古いメモ",
            "updatedAt": 0,
            "canvas": { "elements": [] }
        }
        """
        let decoded = try JSONDecoder().decode(Memo.self, from: Data(json.utf8))

        #expect(decoded.floatingOrigin == nil)
        #expect(decoded.title == "古いメモ")
    }
}
