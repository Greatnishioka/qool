import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 元画像の切り詰めと、使われなくなった画像の掃除の検証。
struct ImageAssetLifecycleTests {
    private let cropGeometry = CutoutCropGeometry()

    private func contour(_ rect: CGRect) -> CanvasPathContour {
        CanvasPathContour(points: [
            NormalizedPoint(x: rect.minX, y: rect.minY),
            NormalizedPoint(x: rect.maxX, y: rect.minY),
            NormalizedPoint(x: rect.maxX, y: rect.maxY),
            NormalizedPoint(x: rect.minX, y: rect.maxY)
        ])
    }

    private func imageElement(contours: [CanvasPathContour], frame: CGRect) -> CanvasElement {
        CanvasElement(
            kind: .imageCutout,
            frame: frame,
            fillColor: .clear,
            pathContours: contours,
            imageAssetID: UUID()
        )
    }

    // MARK: - 切り詰める範囲

    /// 等倍表示なら余白は下限の 48px。
    @Test func 輪郭のまわりに余白を付けて切り詰める() throws {
        let crop = try #require(
            cropGeometry.crop(
                for: [contour(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))],
                imagePixelSize: CGSize(width: 1000, height: 1000),
                displaySize: CGSize(width: 1000, height: 1000)
            )
        )

        #expect(abs(crop.normalizedRect.minX - (0.4 - 0.048)) < 0.001)
        #expect(abs(crop.normalizedRect.width - (0.2 + 0.096)) < 0.001)
    }

    /// **大きな写真を小さく表示しているときが要点です。** 余白は画素、調整はポイントなので、
    /// 画素側を縮尺のぶん広げないと、あとから余白を上げても画像が尽きます。
    @Test func 縮小表示なら余白は縮尺のぶん広がる() throws {
        let crop = try #require(
            cropGeometry.crop(
                for: [contour(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))],
                imagePixelSize: CGSize(width: 2000, height: 2000),
                displaySize: CGSize(width: 320, height: 320)
            )
        )

        // 縮尺は 6.25 倍。調整で広げられるのは 24 + 14 = 38pt なので 237.5px。
        let expectedMargin = CutoutCropGeometry.adjustableMarginPoints * 2000 / 320
        #expect(expectedMargin > CutoutCropGeometry.minimumMarginPixels)
        #expect(abs(crop.pixelRect.minX - (0.4 * 2000 - expectedMargin)) < 1)
        // それでも切り詰める価値は残ります。
        #expect(crop.normalizedRect.width < 0.9)
    }

    @Test func 画像の外へははみ出さない() throws {
        let crop = try #require(
            cropGeometry.crop(
                for: [contour(CGRect(x: 0, y: 0, width: 0.3, height: 0.3))],
                imagePixelSize: CGSize(width: 2000, height: 2000),
                displaySize: CGSize(width: 320, height: 320)
            )
        )

        #expect(crop.normalizedRect.minX >= 0)
        #expect(crop.normalizedRect.minY >= 0)
        #expect(crop.normalizedRect.maxX <= 1)
        #expect(crop.normalizedRect.maxY <= 1)
    }

    /// わずかしか縮まないのに作り直すと、ID が変わって掃除まで走ります。割に合いません。
    @Test func ほとんど縮まないなら切り詰めない() {
        let crop = cropGeometry.crop(
            for: [contour(CGRect(x: 0.02, y: 0.02, width: 0.96, height: 0.96))],
            imagePixelSize: CGSize(width: 1000, height: 1000),
            displaySize: CGSize(width: 1000, height: 1000)
        )

        #expect(crop == nil)
    }

    @Test func 輪郭がなければ切り詰めない() {
        #expect(
            cropGeometry.crop(
                for: [],
                imagePixelSize: CGSize(width: 100, height: 100),
                displaySize: CGSize(width: 100, height: 100)
            ) == nil
        )
    }

    /// 正規化は画素の格子に載せたあとに割り出します。ずれると中身と輪郭が食い違います。
    @Test func 正規化した範囲は切り出す画素とぴったり対応する() throws {
        let pixelSize = CGSize(width: 777, height: 333)
        let crop = try #require(
            cropGeometry.crop(
                for: [contour(CGRect(x: 0.3137, y: 0.2891, width: 0.2113, height: 0.1777))],
                imagePixelSize: pixelSize,
                displaySize: pixelSize
            )
        )

        #expect(crop.pixelRect == crop.pixelRect.integral)
        #expect(abs(crop.normalizedRect.minX * pixelSize.width - crop.pixelRect.minX) < 0.0001)
        #expect(abs(crop.normalizedRect.width * pixelSize.width - crop.pixelRect.width) < 0.0001)
    }

    // MARK: - 切り詰めた後の見た目

    /// **これが要点です。** 画像を小さくしても、輪郭が画面上で指す位置は動いてはいけません。
    @Test func 切り詰めても輪郭の絶対位置は変わらない() throws {
        let frame = CGRect(x: 100, y: 200, width: 400, height: 300)
        let original = imageElement(
            contours: [contour(CGRect(x: 0.3, y: 0.25, width: 0.4, height: 0.5))],
            frame: frame
        )
        let crop = try #require(
            cropGeometry.crop(
                for: original.pathContours,
                imagePixelSize: CGSize(width: 800, height: 600),
                displaySize: frame.size
            )
        )

        let cropped = cropGeometry.applied(crop, to: original, assetID: UUID())

        for (before, after) in zip(original.pathContours[0].points, cropped.pathContours[0].points) {
            let beforePoint = CGPoint(
                x: frame.minX + before.x * frame.width,
                y: frame.minY + before.y * frame.height
            )
            let afterPoint = CGPoint(
                x: cropped.frame.minX + after.x * cropped.frame.width,
                y: cropped.frame.minY + after.y * cropped.frame.height
            )

            #expect(abs(beforePoint.x - afterPoint.x) < 0.0001)
            #expect(abs(beforePoint.y - afterPoint.y) < 0.0001)
        }
    }

    @Test func 切り詰めると枠が小さくなり新しい画像を指す() throws {
        let original = imageElement(
            contours: [contour(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))],
            frame: CGRect(x: 0, y: 0, width: 400, height: 400)
        )
        let crop = try #require(
            cropGeometry.crop(
                for: original.pathContours,
                imagePixelSize: CGSize(width: 1000, height: 1000),
                displaySize: original.frame.size
            )
        )
        let newAssetID = UUID()

        let cropped = cropGeometry.applied(crop, to: original, assetID: newAssetID)

        #expect(cropped.frame.width < original.frame.width)
        #expect(cropped.imageAssetID == newAssetID)
    }

    // MARK: - 使われなくなった画像の掃除

    private func withTemporaryRepository(
        _ body: (FileImageAssetRepositoryInfrastructure) throws -> Void
    ) throws {
        let root = URL.temporaryDirectory.appending(
            path: "qool-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try body(FileImageAssetRepositoryInfrastructure(rootDirectory: root))
    }

    private let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    @Test func 参照されていない画像は消える() throws {
        try withTemporaryRepository { repository in
            let memo = Memo(title: "掃除")
            let usedID = try repository.save(pngHeader, in: memo.id)
            let orphanID = try repository.save(pngHeader, in: memo.id)

            var canvas = Canvas()
            canvas.elements = [
                CanvasElement(kind: .imageCutout, frame: .zero, fillColor: .clear, imageAssetID: usedID)
            ]
            var updatedMemo = memo
            updatedMemo.canvas = canvas

            try PruneImageAssetsUseCase(repository: repository)(for: updatedMemo)

            #expect(repository.data(for: usedID, in: memo.id) != nil)
            #expect(repository.data(for: orphanID, in: memo.id) == nil)
        }
    }

    /// 結合は解けます。解いた先の画像を消すと、戻した要素に絵がありません。
    @Test func 結合の元要素が持つ画像は残る() throws {
        try withTemporaryRepository { repository in
            let memo = Memo(title: "結合")
            let sourceAssetID = try repository.save(pngHeader, in: memo.id)
            let sourceElement = CanvasElement(
                kind: .imageCutout,
                frame: .zero,
                fillColor: .clear,
                imageAssetID: sourceAssetID
            )
            var updatedMemo = memo
            updatedMemo.canvas.elements = [
                CanvasElement(
                    kind: .path,
                    frame: .zero,
                    fillColor: .paper,
                    unionSourceElements: [CanvasElementSnapshot(element: sourceElement)]
                )
            ]

            try PruneImageAssetsUseCase(repository: repository)(for: updatedMemo)

            #expect(repository.data(for: sourceAssetID, in: memo.id) != nil)
        }
    }

    /// **掃除が走るのは読み込み直後だけです。** 編集の途中で消すと、
    /// まとめ書きが確定する前に落ちたときメモが存在しない画像を指します。
    @MainActor
    @Test func 読み込み直後に孤児が消える() async throws {
        let root = URL.temporaryDirectory.appending(
            path: "qool-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let imageRepository = FileImageAssetRepositoryInfrastructure(rootDirectory: root)
        let memoRepository = InMemoryMemoRepositoryInfrastructure()

        var memo = Memo(title: "掃除")
        let usedID = try imageRepository.save(pngHeader, in: memo.id)
        let orphanID = try imageRepository.save(pngHeader, in: memo.id)
        memo.canvas.elements = [
            CanvasElement(kind: .imageCutout, frame: .zero, fillColor: .clear, imageAssetID: usedID)
        ]
        try await memoRepository.save(memo)

        _ = AppRootViewModel.bootstrap(repository: memoRepository, imageRepository: imageRepository)

        #expect(imageRepository.data(for: usedID, in: memo.id) != nil)
        #expect(imageRepository.data(for: orphanID, in: memo.id) == nil)
    }

    @Test func 画像を持たないメモでも失敗しない() throws {
        try withTemporaryRepository { repository in
            try PruneImageAssetsUseCase(repository: repository)(for: Memo(title: "空"))
        }
    }
}
