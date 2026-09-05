import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 画像の取り込み（[CanvasViewModel.importImage](../qool/Presentation/ViewModels/CanvasViewModel.swift)）の検証。
/// `NSImage` → PNG → 保存 → 要素 → 読み戻し、という経路をまとめて通します。
@MainActor
struct CanvasImageImportTests {
    private func withTemporaryCanvas(
        _ body: (CanvasViewModel, URL) throws -> Void
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
            pruneImageAssetsUseCase: PruneImageAssetsUseCase(repository: repository),
            onSave: { _ in }
        )

        try body(viewModel, root)
    }

    /// 指定した大きさの PNG を書き出す。
    private func writeImage(width: Int, height: Int, to directory: URL) throws -> URL {
        let image = NSImage(size: CGSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemTeal.drawSwatch(in: CGRect(x: 0, y: 0, width: width, height: height))
        image.unlockFocus()

        let data = try #require(CanvasImageStore.pngData(from: image))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "source.png")
        try data.write(to: url)

        return url
    }

    @Test func 取り込むと画像要素が1つ増える() throws {
        try withTemporaryCanvas { viewModel, root in
            let url = try writeImage(width: 200, height: 100, to: root)

            let didImport = viewModel.importImage(
                from: url,
                at: CGPoint(x: 200, y: 200),
                canvasSize: CGSize(width: 600, height: 600)
            )

            #expect(didImport)
            #expect(viewModel.memo.canvas.elements.count == 1)
            #expect(viewModel.memo.canvas.elements.first?.kind == .imageCutout)
            #expect(viewModel.memo.canvas.elements.first?.imageAssetID != nil)
        }
    }

    /// `Memo` は値型なので画像そのものは持ちません。ID から引き当てられることを確認します。
    @Test func 取り込んだ画像をIDから引き当てられる() throws {
        try withTemporaryCanvas { viewModel, root in
            let url = try writeImage(width: 200, height: 100, to: root)
            viewModel.importImage(from: url, at: .zero, canvasSize: CGSize(width: 600, height: 600))

            let element = try #require(viewModel.memo.canvas.elements.first)

            #expect(viewModel.image(for: element) != nil)
        }
    }

    @Test func 画像を持たない要素はnilを返す() throws {
        try withTemporaryCanvas { viewModel, _ in
            let element = CanvasElement(
                kind: .rectangle,
                frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                fillColor: .paper
            )

            #expect(viewModel.image(for: element) == nil)
        }
    }

    /// 長辺を 320pt に収め、縦横比は保ちます。
    @Test func 大きい画像は長辺320に収まる() throws {
        try withTemporaryCanvas { viewModel, root in
            let url = try writeImage(width: 1600, height: 800, to: root)

            viewModel.importImage(
                from: url,
                at: CGPoint(x: 300, y: 300),
                canvasSize: CGSize(width: 800, height: 800)
            )

            let frame = try #require(viewModel.memo.canvas.elements.first?.frame)
            #expect(abs(frame.width - 320) < 0.001)
            #expect(abs(frame.height - 160) < 0.001)
        }
    }

    @Test func 小さい画像は拡大しない() throws {
        try withTemporaryCanvas { viewModel, root in
            let url = try writeImage(width: 40, height: 30, to: root)

            viewModel.importImage(from: url, at: CGPoint(x: 300, y: 300), canvasSize: CGSize(width: 800, height: 800))

            let frame = try #require(viewModel.memo.canvas.elements.first?.frame)
            #expect(abs(frame.width - 40) < 0.001)
            #expect(abs(frame.height - 30) < 0.001)
        }
    }

    /// 端に落としてもキャンバスの外へは出しません。
    @Test func キャンバスの外へはみ出さない() throws {
        try withTemporaryCanvas { viewModel, root in
            let url = try writeImage(width: 320, height: 320, to: root)

            viewModel.importImage(from: url, at: .zero, canvasSize: CGSize(width: 400, height: 400))

            let frame = try #require(viewModel.memo.canvas.elements.first?.frame)
            #expect(frame.minX >= 0)
            #expect(frame.minY >= 0)
            #expect(frame.maxX <= 400)
            #expect(frame.maxY <= 400)
        }
    }

    @Test func 画像として読めないファイルは取り込まない() throws {
        try withTemporaryCanvas { viewModel, root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appending(path: "broken.png")
            try Data("これは画像ではありません".utf8).write(to: url)

            let didImport = viewModel.importImage(from: url, at: .zero, canvasSize: CGSize(width: 400, height: 400))

            #expect(didImport == false)
            #expect(viewModel.memo.canvas.elements.isEmpty)
        }
    }

    @Test func 取り込むと選択ツールへ戻り新しい要素が選ばれる() throws {
        try withTemporaryCanvas { viewModel, root in
            let url = try writeImage(width: 100, height: 100, to: root)
            viewModel.selectTool(.rectangle)

            viewModel.importImage(from: url, at: .zero, canvasSize: CGSize(width: 400, height: 400))

            let element = try #require(viewModel.memo.canvas.elements.first)
            #expect(viewModel.selectedTool == .select)
            #expect(viewModel.selectedElementIDs == [element.id])
        }
    }
}
