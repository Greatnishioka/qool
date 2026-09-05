import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 切り抜き（なぞり → 輪郭 → 要素へ反映）の検証。
@MainActor
struct CanvasCutoutTests {
    private func withImportedImage(
        _ body: (CanvasViewModel, CanvasElement) throws -> Void
    ) throws {
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
            onSave: { _ in }
        )

        let image = NSImage(size: CGSize(width: 200, height: 200))
        image.lockFocus()
        NSColor.systemTeal.drawSwatch(in: CGRect(x: 0, y: 0, width: 200, height: 200))
        image.unlockFocus()

        viewModel.importImage(image, at: CGPoint(x: 200, y: 200), canvasSize: CGSize(width: 600, height: 600))
        let element = try #require(viewModel.memo.canvas.elements.first)

        try body(viewModel, element)
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

    @Test func なぞりから輪郭ができる() throws {
        try withImportedImage { viewModel, element in
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
    @Test func 輪郭は正規化座標に収まる() throws {
        try withImportedImage { viewModel, element in
            viewModel.applyCutout(tracePoints: squareTrace(), to: element.id)

            let points = try #require(viewModel.memo.canvas.elements.first?.pathContours.first?.points)
            #expect(points.allSatisfy { $0.x >= -0.001 && $0.x <= 1.001 })
            #expect(points.allSatisfy { $0.y >= -0.001 && $0.y <= 1.001 })
        }
    }

    /// 元画像は残ります。切り抜き後もなぞり直せることの前提です。
    @Test func 切り抜いても元画像の参照は残る() throws {
        try withImportedImage { viewModel, element in
            viewModel.applyCutout(tracePoints: squareTrace(), to: element.id)

            let updated = try #require(viewModel.memo.canvas.elements.first)
            #expect(updated.imageAssetID == element.imageAssetID)
            #expect(viewModel.image(for: updated) != nil)
        }
    }

    @Test func 点が足りなければ何も変えない() throws {
        try withImportedImage { viewModel, element in
            let didApply = viewModel.applyCutout(
                tracePoints: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.2)],
                to: element.id
            )

            #expect(didApply == false)
            #expect(viewModel.memo.canvas.elements.first?.pathContours.isEmpty == true)
        }
    }

    @Test func 空のなぞりは何も変えない() throws {
        try withImportedImage { viewModel, element in
            #expect(viewModel.applyCutout(tracePoints: [], to: element.id) == false)
        }
    }

    @Test func 解除すると輪郭が消える() throws {
        try withImportedImage { viewModel, element in
            viewModel.applyCutout(tracePoints: squareTrace(), to: element.id)
            #expect(viewModel.memo.canvas.elements.first?.pathContours.isEmpty == false)

            viewModel.clearCutout(of: element.id)

            #expect(viewModel.memo.canvas.elements.first?.pathContours.isEmpty == true)
            // 画像は消しません。もう一度なぞれます。
            #expect(viewModel.memo.canvas.elements.first?.imageAssetID != nil)
        }
    }

    /// 候補を作るだけでは要素を変えません。
    @Test func 候補の生成は要素を変えない() throws {
        try withImportedImage { viewModel, element in
            let candidates = viewModel.cutoutCandidates(tracePoints: squareTrace())

            #expect(candidates.isEmpty == false)
            #expect(viewModel.memo.canvas.elements.first?.pathContours.isEmpty == true)
        }
    }

    /// 候補から選んだ輪郭も反映できます。
    @Test func 候補を選んで適用できる() throws {
        try withImportedImage { viewModel, element in
            let candidates = viewModel.cutoutCandidates(tracePoints: squareTrace())
            let recommended = try #require(candidates.first { $0.isRecommended })

            let didApply = viewModel.applyCutout(contours: recommended.contours, to: element.id)

            #expect(didApply)
            #expect(viewModel.memo.canvas.elements.first?.pathContours.count == 1)
        }
    }

    /// なぞりの角は残ります（`ContourSmoother` のアンカー保護）。
    @Test func 四角くなぞると角が残る() throws {
        try withImportedImage { viewModel, element in
            viewModel.applyCutout(tracePoints: squareTrace(), to: element.id)

            let points = try #require(viewModel.memo.canvas.elements.first?.pathContours.first?.points)
            let corners = [
                CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.2),
                CGPoint(x: 0.8, y: 0.8), CGPoint(x: 0.2, y: 0.8)
            ]

            for corner in corners {
                let distance = points.map { hypot($0.x - corner.x, $0.y - corner.y) }.min() ?? 1
                #expect(distance < 0.05, "角 \(corner) が \(distance) まで丸まった")
            }
        }
    }
}
