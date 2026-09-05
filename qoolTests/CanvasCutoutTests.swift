import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 切り抜き（なぞり → 輪郭 → 要素へ反映）の検証。
@MainActor
struct CanvasCutoutTests {
    private func withImportedImage(
        _ body: (CanvasViewModel, CanvasElement, NSImage) async throws -> Void
    ) async throws {
        let root = URL.temporaryDirectory.appending(
            path: "qool-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileImageAssetRepositoryInfrastructure(rootDirectory: root)
        let viewModel = CanvasViewModel(
            memo: Memo(title: "テスト"),
            imageStore: CanvasImageStore(repository: repository),
            importImageUseCase: ImportImageUseCase(repository: repository),
            pruneImageAssetsUseCase: PruneImageAssetsUseCase(repository: repository),
            onSave: { _ in }
        )

        let image = NSImage(size: CGSize(width: 200, height: 200))
        image.lockFocus()
        NSColor.systemTeal.drawSwatch(in: CGRect(x: 0, y: 0, width: 200, height: 200))
        image.unlockFocus()

        viewModel.importImage(image, at: CGPoint(x: 200, y: 200), canvasSize: CGSize(width: 600, height: 600))
        let element = try #require(viewModel.memo.canvas.elements.first)

        try await body(viewModel, element, image)
    }

    /// 正方形をなぞった想定の点列。
    private func squareTrace() -> [CGPoint] {
        var points: [CGPoint] = []
        let steps = 20

        for index in 0..<steps {
            points.append(CGPoint(x: 0.2 + 0.6 * CGFloat(index) / CGFloat(steps), y: 0.2))
        }
        for index in 0..<steps {
            points.append(CGPoint(x: 0.8, y: 0.2 + 0.6 * CGFloat(index) / CGFloat(steps)))
        }
        for index in 0..<steps {
            points.append(CGPoint(x: 0.8 - 0.6 * CGFloat(index) / CGFloat(steps), y: 0.8))
        }
        for index in 0..<steps {
            points.append(CGPoint(x: 0.2, y: 0.8 - 0.6 * CGFloat(index) / CGFloat(steps)))
        }

        return points
    }

    @Test func なぞりから輪郭ができる() async throws {
        try await withImportedImage { viewModel, element, image in
            #expect(element.pathContours.isEmpty)

            let didApply = viewModel.applyCutout(tracePoints: squareTrace(), to: element.id)

            #expect(didApply)
            let updated = try #require(viewModel.memo.canvas.elements.first)
            #expect(updated.pathContours.count == 1)
            #expect(updated.pathContours[0].points.count >= 3)
            #expect(updated.isClosedPath)
        }
    }

    /// 輪郭は画像の表示矩形を基準にした正規化座標です。
    @Test func 輪郭は正規化座標に収まる() async throws {
        try await withImportedImage { viewModel, element, image in
            viewModel.applyCutout(tracePoints: squareTrace(), to: element.id)

            let points = try #require(viewModel.memo.canvas.elements.first?.pathContours.first?.points)
            #expect(points.allSatisfy { $0.x >= -0.001 && $0.x <= 1.001 })
            #expect(points.allSatisfy { $0.y >= -0.001 && $0.y <= 1.001 })
        }
    }

    /// 元画像は残ります。切り抜き後もなぞり直せることの前提です。
    /// 保存されるのは切り抜き結果ではなく元画像です。あとからなぞり直せる必要があります。
    /// **画像の ID は見ません。** 切り詰めが走ると差し替わるためです（下の専用のテストで見ます）。
    @Test func 切り抜いても元画像は引ける() async throws {
        try await withImportedImage { viewModel, element, image in
            viewModel.applyCutout(tracePoints: squareTrace(), to: element.id)

            let updated = try #require(viewModel.memo.canvas.elements.first)
            #expect(updated.imageAssetID != nil)
            #expect(viewModel.image(for: updated) != nil)
        }
    }

    /// 元画像を輪郭のまわりまで切り詰め、原寸のほうを片付けることの確認。
    @Test func 切り抜くと元画像が切り詰められ原寸は消える() async throws {
        let root = URL.temporaryDirectory.appending(
            path: "qool-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileImageAssetRepositoryInfrastructure(rootDirectory: root)
        let viewModel = CanvasViewModel(
            memo: Memo(title: "テスト"),
            imageStore: CanvasImageStore(repository: repository),
            importImageUseCase: ImportImageUseCase(repository: repository),
            pruneImageAssetsUseCase: PruneImageAssetsUseCase(repository: repository),
            onSave: { _ in }
        )

        // 余白 48px を引いても十分小さくなるよう、大きめの画像を使います。
        // 小さい画像だと余白のほうが勝ち、切り詰める意味がなくなります。
        let image = NSImage(size: CGSize(width: 800, height: 800))
        image.lockFocus()
        NSColor.systemTeal.drawSwatch(in: CGRect(x: 0, y: 0, width: 800, height: 800))
        image.unlockFocus()

        viewModel.importImage(image, at: CGPoint(x: 400, y: 400), canvasSize: CGSize(width: 900, height: 900))
        let element = try #require(viewModel.memo.canvas.elements.first)
        let originalAssetID = try #require(element.imageAssetID)

        viewModel.applyCutout(tracePoints: squareTrace(), to: element.id)

        let updated = try #require(viewModel.memo.canvas.elements.first)
        #expect(updated.imageAssetID != originalAssetID)
        #expect(viewModel.image(for: updated) != nil)
        #expect(updated.frame.width < element.frame.width)
        // 原寸のファイルは掃除されます。
        #expect(repository.data(for: originalAssetID, in: viewModel.memo.id) == nil)
    }

    @Test func 点が足りなければ何も変えない() async throws {
        try await withImportedImage { viewModel, element, image in
            let didApply = viewModel.applyCutout(
                tracePoints: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.2)],
                to: element.id
            )

            #expect(didApply == false)
            #expect(viewModel.memo.canvas.elements.first?.pathContours.isEmpty == true)
        }
    }

    @Test func 空のなぞりは何も変えない() async throws {
        try await withImportedImage { viewModel, element, image in
            #expect(viewModel.applyCutout(tracePoints: [], to: element.id) == false)
        }
    }

    @Test func 解除すると輪郭が消える() async throws {
        try await withImportedImage { viewModel, element, image in
            viewModel.applyCutout(tracePoints: squareTrace(), to: element.id)
            #expect(viewModel.memo.canvas.elements.first?.pathContours.isEmpty == false)

            viewModel.clearCutout(of: element.id)

            #expect(viewModel.memo.canvas.elements.first?.pathContours.isEmpty == true)
            // 画像は消しません。もう一度なぞれます。
            #expect(viewModel.memo.canvas.elements.first?.imageAssetID != nil)
        }
    }

    /// 候補を作るだけでは要素を変えません。
    @Test func 候補の生成は要素を変えない() async throws {
        try await withImportedImage { viewModel, element, image in
            let candidates = await viewModel.cutoutCandidates(image: image, tracePoints: squareTrace())

            #expect(candidates.isEmpty == false)
            #expect(viewModel.memo.canvas.elements.first?.pathContours.isEmpty == true)
        }
    }

    /// 候補から選んだ輪郭も反映できます。
    @Test func 候補を選んで適用できる() async throws {
        try await withImportedImage { viewModel, element, image in
            let candidates = await viewModel.cutoutCandidates(image: image, tracePoints: squareTrace())
            let recommended = try #require(candidates.first { $0.isRecommended })

            let didApply = viewModel.applyCutout(contours: recommended.contours, to: element.id)

            #expect(didApply)
            #expect(viewModel.memo.canvas.elements.first?.pathContours.count == 1)
        }
    }

    /// なぞりの角は残ります（`ContourSmoother` のアンカー保護）。
    @Test func 四角くなぞると角が残る() async throws {
        try await withImportedImage { viewModel, element, image in
            viewModel.applyCutout(tracePoints: squareTrace(), to: element.id)

            let updated = try #require(viewModel.memo.canvas.elements.first)
            let points = try #require(updated.pathContours.first?.points)

            // **キャンバス上の絶対位置で比べます。** 切り詰めが走ると枠と正規化の基準が変わるため、
            // 正規化座標のまま比べると、形が同じでも数値がずれます。
            let absolutePoints = points.map { point in
                CGPoint(
                    x: updated.frame.minX + point.x * updated.frame.width,
                    y: updated.frame.minY + point.y * updated.frame.height
                )
            }
            let corners = [(0.2, 0.2), (0.8, 0.2), (0.8, 0.8), (0.2, 0.8)].map { corner in
                CGPoint(
                    x: element.frame.minX + corner.0 * element.frame.width,
                    y: element.frame.minY + corner.1 * element.frame.height
                )
            }
            let tolerance = element.frame.width * 0.05

            for corner in corners {
                let distance = absolutePoints.map { hypot($0.x - corner.x, $0.y - corner.y) }.min() ?? .infinity
                #expect(distance < tolerance, "角 \(corner) が \(distance) まで丸まった")
            }
        }
    }
}
