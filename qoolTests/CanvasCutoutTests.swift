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
            maskStore: CutoutMaskStore(repository: repository),
            importImageUseCase: ImportImageUseCase(repository: repository),
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

    /// 元画像を輪郭のまわりまで切り詰めることの確認。
    ///
    /// **原寸のファイルはここでは消えません。** 消すのは読み込み直後だけで、
    /// 保存が確定する前に消すと、落ちたときにメモが存在しない画像を指すためです。
    @Test func 切り抜くと元画像が切り詰められる() async throws {
        let root = URL.temporaryDirectory.appending(
            path: "qool-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileImageAssetRepositoryInfrastructure(rootDirectory: root)
        let viewModel = CanvasViewModel(
            memo: Memo(title: "テスト"),
            imageStore: CanvasImageStore(repository: repository),
            maskStore: CutoutMaskStore(repository: repository),
            importImageUseCase: ImportImageUseCase(repository: repository),
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
        // 原寸はまだ残っています（掃除は次回の読み込み時）。
        #expect(repository.data(for: originalAssetID, in: viewModel.memo.id) != nil)
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

    /// 解除で切り詰め前の絵と枠へ戻ることの確認。
    ///
    /// **輪郭を消すだけでは足りません。** 適用時に「輪郭 + 余白」まで切り詰めているので、
    /// 画像を戻さないと余白ぶんだけ縮んだ絵が残ります。
    @Test func 解除すると切り詰める前の画像へ戻る() async throws {
        let root = URL.temporaryDirectory.appending(
            path: "qool-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileImageAssetRepositoryInfrastructure(rootDirectory: root)
        let viewModel = CanvasViewModel(
            memo: Memo(title: "テスト"),
            imageStore: CanvasImageStore(repository: repository),
            maskStore: CutoutMaskStore(repository: repository),
            importImageUseCase: ImportImageUseCase(repository: repository),
            onSave: { _ in }
        )

        let image = NSImage(size: CGSize(width: 800, height: 800))
        image.lockFocus()
        NSColor.systemTeal.drawSwatch(in: CGRect(x: 0, y: 0, width: 800, height: 800))
        image.unlockFocus()

        viewModel.importImage(image, at: CGPoint(x: 400, y: 400), canvasSize: CGSize(width: 900, height: 900))
        let element = try #require(viewModel.memo.canvas.elements.first)
        let originalAssetID = try #require(element.imageAssetID)

        viewModel.applyCutout(tracePoints: squareTrace(), to: element.id)
        let cropped = try #require(viewModel.memo.canvas.elements.first)
        #expect(cropped.imageAssetID != originalAssetID)

        viewModel.clearCutout(of: element.id)

        let restored = try #require(viewModel.memo.canvas.elements.first)
        #expect(restored.imageAssetID == originalAssetID)
        #expect(restored.imageSource == nil)
        #expect(abs(restored.frame.width - element.frame.width) < 0.0001)
        #expect(abs(restored.frame.height - element.frame.height) < 0.0001)
        #expect(abs(restored.frame.minX - element.frame.minX) < 0.0001)
        #expect(abs(restored.frame.minY - element.frame.minY) < 0.0001)
        #expect(viewModel.image(for: restored) != nil)
    }

    /// **適用でマスクが焼かれることの確認。** 輪郭も残します。
    /// マスクを読めなかったときの描画と、なぞり直しの土台に要るためです。
    @Test func 切り抜くとマスクが焼かれる() async throws {
        try await withImportedImage { viewModel, element, image in
            viewModel.applyCutout(tracePoints: squareTrace(), to: element.id)

            let updated = try #require(viewModel.memo.canvas.elements.first)

            #expect(updated.cutoutMask != nil)
            #expect(!updated.pathContours.isEmpty)
            // 描画に使う形は裏で用意されるので、待ってから確かめます。
            #expect(await viewModel.cutoutMask(for: updated) != nil)
        }
    }

    /// マスクは切り詰めたあとに焼きます。先に焼くと画素の意味する範囲がずれます。
    @Test func マスクの覆う範囲は輪郭に沿って絞られる() async throws {
        try await withImportedImage { viewModel, element, image in
            viewModel.applyCutout(tracePoints: squareTrace(), to: element.id)

            let updated = try #require(viewModel.memo.canvas.elements.first)
            let extent = try #require(updated.cutoutMask?.extent)

            // 全面ではなく、輪郭のある範囲まで絞られています。
            #expect(extent.width <= 1)
            #expect(extent.height <= 1)
            #expect(extent.width > 0)
        }
    }

    @Test func 解除するとマスクも捨てる() async throws {
        try await withImportedImage { viewModel, element, image in
            viewModel.applyCutout(tracePoints: squareTrace(), to: element.id)
            #expect(viewModel.memo.canvas.elements.first?.cutoutMask != nil)

            viewModel.clearCutout(of: element.id)

            let updated = try #require(viewModel.memo.canvas.elements.first)
            #expect(updated.cutoutMask == nil)
            #expect(await viewModel.cutoutMask(for: updated) == nil)
        }
    }

    /// **マスクを渡せば、輪郭はそこから導かれます。**
    /// 手直しはマスクに対して行うので、渡された輪郭は古いことがあります。
    @Test func マスクを渡すと輪郭はマスクから導かれる() async throws {
        try await withImportedImage { viewModel, element, image in
            // 中央だけを覆うマスク。渡す輪郭とは形が違います。
            var coverage = [UInt8](repeating: 0, count: 64 * 64)
            for row in 20..<44 {
                for column in 20..<44 {
                    coverage[row * 64 + column] = 255
                }
            }
            let mask = try #require(CutoutMask(width: 64, height: 64, coverage: coverage))

            // 画面いっぱいの輪郭を渡しますが、マスクが優先されます。
            let wide = CanvasPathContour(points: [
                NormalizedPoint(x: 0, y: 0),
                NormalizedPoint(x: 1, y: 0),
                NormalizedPoint(x: 1, y: 1),
                NormalizedPoint(x: 0, y: 1)
            ])

            #expect(viewModel.applyCutout(contours: [wide], mask: mask, to: element.id))

            let updated = try #require(viewModel.memo.canvas.elements.first)
            let points = try #require(updated.pathContours.first).points
            let minimumX = points.map(\.x).min() ?? 0

            #expect(updated.cutoutMask != nil)
            // 導かれた輪郭は中央の範囲に収まり、渡した全面の輪郭ではありません。
            #expect(minimumX > 0.1)
        }
    }

    /// **既存の切り抜きがあっても、新しい形で置き換わります。**
    /// 手描きと矩形補正はマスクを持たないので、土台に既存のマスクを選ぶと
    /// 新しい輪郭が捨てられ、古い切り抜きのまま適用されます。
    @Test func マスクのない輪郭で既存の切り抜きを置き換えられる() async throws {
        try await withImportedImage { viewModel, element, image in
            // 中央だけを覆うマスクで 1 度切り抜きます。
            var coverage = [UInt8](repeating: 0, count: 64 * 64)
            for row in 22..<42 {
                for column in 22..<42 {
                    coverage[row * 64 + column] = 255
                }
            }
            let central = try #require(CutoutMask(width: 64, height: 64, coverage: coverage))

            #expect(viewModel.applyCutout(contours: [], mask: central, to: element.id))

            let cutout = try #require(viewModel.memo.canvas.elements.first)
            let before = try #require(await viewModel.cutoutMask(for: cutout))
            let cornerBefore = before.value(at: CGPoint(x: 0.05, y: 0.05))

            #expect(cornerBefore == 0)

            // ほぼ全面の輪郭を、マスクなしで適用します（手描き・矩形補正の経路）。
            let wide = CanvasPathContour(points: [
                NormalizedPoint(x: 0.02, y: 0.02),
                NormalizedPoint(x: 0.98, y: 0.02),
                NormalizedPoint(x: 0.98, y: 0.98),
                NormalizedPoint(x: 0.02, y: 0.98)
            ])

            #expect(viewModel.applyCutout(contours: [wide], mask: nil, to: element.id))

            let updated = try #require(viewModel.memo.canvas.elements.first)
            let after = try #require(await viewModel.cutoutMask(for: updated))
            let cornerAfter = after.value(at: CGPoint(x: 0.05, y: 0.05))

            // 古いマスクが土台に残っていれば、ここは 0 のままです。
            #expect(cornerAfter > 200)
        }
    }

    /// **薄い被覆は輪郭の外にあります。** 輪郭はしきい値を超えた濃さしか表さないので、
    /// 輪郭だけで切り詰め先を決めると、髪やガラスにあたる部分の画像が捨てられます。
    /// 濃い核だけなら切り詰められること（`切り抜くと元画像が切り詰められる`）との対です。
    @Test func 薄い被覆があれば元画像を切り詰めない() async throws {
        try await withImportedImage { viewModel, element, image in
            var coverage = [UInt8](repeating: 0, count: 64 * 64)

            // ほぼ全面を薄く覆います。輪郭にはなりません。
            for row in 4..<60 {
                for column in 4..<60 {
                    coverage[row * 64 + column] = 40
                }
            }
            // 中央の濃い核。輪郭になるのはここだけです。
            for row in 26..<38 {
                for column in 26..<38 {
                    coverage[row * 64 + column] = 255
                }
            }
            let mask = try #require(CutoutMask(width: 64, height: 64, coverage: coverage))

            #expect(viewModel.applyCutout(contours: [], mask: mask, to: element.id))

            let updated = try #require(viewModel.memo.canvas.elements.first)

            // 核だけで決めていれば、その周りまで切り詰められて `imageSource` が付きます。
            #expect(updated.imageSource == nil)

            let stored = try #require(await viewModel.cutoutMask(for: updated))
            let faint = stored.value(at: CGPoint(x: 0.1, y: 0.1))

            // 薄い覆いが 2 値へ潰れていないこと。
            #expect(faint > 0)
            #expect(faint < 128)
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
