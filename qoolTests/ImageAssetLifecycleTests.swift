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

    @Test func 輪郭のまわりに余白を付けて切り詰める() throws {
        let pixelSize = CGSize(width: 1000, height: 1000)
        let cropRect = try #require(
            cropGeometry.cropRect(for: [contour(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))], imagePixelSize: pixelSize)
        )

        // 48px = 正規化して 0.048。
        #expect(abs(cropRect.minX - (0.4 - 0.048)) < 0.0001)
        #expect(abs(cropRect.width - (0.2 + 0.096)) < 0.0001)
    }

    @Test func 画像の外へははみ出さない() throws {
        let cropRect = try #require(
            cropGeometry.cropRect(
                for: [contour(CGRect(x: 0, y: 0, width: 0.3, height: 0.3))],
                imagePixelSize: CGSize(width: 200, height: 200)
            )
        )

        #expect(cropRect.minX >= 0)
        #expect(cropRect.minY >= 0)
        #expect(cropRect.maxX <= 1)
        #expect(cropRect.maxY <= 1)
    }

    /// わずかしか縮まないのに作り直すと、ID が変わって掃除まで走ります。割に合いません。
    @Test func ほとんど縮まないなら切り詰めない() {
        let cropRect = cropGeometry.cropRect(
            for: [contour(CGRect(x: 0.02, y: 0.02, width: 0.96, height: 0.96))],
            imagePixelSize: CGSize(width: 1000, height: 1000)
        )

        #expect(cropRect == nil)
    }

    @Test func 輪郭がなければ切り詰めない() {
        #expect(cropGeometry.cropRect(for: [], imagePixelSize: CGSize(width: 100, height: 100)) == nil)
    }

    // MARK: - 切り詰めた後の見た目

    /// **これが要点です。** 画像を小さくしても、輪郭が画面上で指す位置は動いてはいけません。
    @Test func 切り詰めても輪郭の絶対位置は変わらない() throws {
        let frame = CGRect(x: 100, y: 200, width: 400, height: 300)
        let original = imageElement(
            contours: [contour(CGRect(x: 0.3, y: 0.25, width: 0.4, height: 0.5))],
            frame: frame
        )
        let cropRect = try #require(
            cropGeometry.cropRect(for: original.pathContours, imagePixelSize: CGSize(width: 800, height: 600))
        )

        let cropped = cropGeometry.applied(cropRect, to: original, assetID: UUID())

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
        let cropRect = try #require(
            cropGeometry.cropRect(for: original.pathContours, imagePixelSize: CGSize(width: 1000, height: 1000))
        )
        let newAssetID = UUID()

        let cropped = cropGeometry.applied(cropRect, to: original, assetID: newAssetID)

        #expect(cropped.frame.width < original.frame.width)
        #expect(cropped.imageAssetID == newAssetID)
    }

    @Test func 画素の範囲は格子に載る() {
        let pixelRect = cropGeometry.pixelRect(
            for: CGRect(x: 0.1234, y: 0.5678, width: 0.3, height: 0.3),
            imagePixelSize: CGSize(width: 777, height: 333)
        )

        #expect(pixelRect == pixelRect.integral)
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

    @Test func 画像を持たないメモでも失敗しない() throws {
        try withTemporaryRepository { repository in
            try PruneImageAssetsUseCase(repository: repository)(for: Memo(title: "空"))
        }
    }
}
