import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import qool

/// マスクの保存・読み戻しと、要素からの参照の検証。
@MainActor
struct CutoutMaskStorageTests {
    private let codec = CutoutMaskPNGCodec()
    private let rasterizer = CutoutMaskRasterizer()

    /// **アプリの外で作った PNG です。** 自前の符号化を通さないので、
    /// 復号だけを独立に検証できます。4×2 のグレースケールで、
    /// 1 行目が `255,200,150,100`、2 行目が `10,20,30,40`。
    private static let fixturePNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAAAAABawyK/AAAAEklEQVR4nGP4f2JaCgOXiJwGABZ7Aya14ykVAAAAAElFTkSuQmCC"
    )

    private func gradientMask(width: Int = 8, height: Int = 4) -> CutoutMask? {
        let coverage = (0..<(width * height)).map { index in
            UInt8(index * 255 / max(1, width * height - 1))
        }

        return CutoutMask(width: width, height: height, coverage: coverage)
    }

    private func makeReference(_ assetID: UUID, _ extent: CGRect) -> CutoutMaskReference? {
        CutoutMaskReference(assetID: assetID, extent: extent)
    }

    // MARK: - 復号（片方向）

    /// **自前の符号化に頼らない検証です。** 往復だけだと、符号化と復号が
    /// 互いの間違いを打ち消しても通ってしまいます。
    @Test func 外部で作ったPNGを画素の並びどおりに読む() throws {
        let data = try #require(Self.fixturePNG)

        let mask = try #require(codec.decode(data, extent: CGRect(x: 0, y: 0, width: 1, height: 1)))

        #expect(mask.width == 4)
        #expect(mask.height == 2)
        // 先頭が 1 行目の左端。ここが崩れると上下が裏返ります。
        #expect(mask.coverage == [255, 200, 150, 100, 10, 20, 30, 40])
    }

    @Test func 外部で作ったPNGの上下が保たれる() throws {
        let data = try #require(Self.fixturePNG)

        let mask = try #require(codec.decode(data, extent: CGRect(x: 0, y: 0, width: 1, height: 1)))

        // 上の行のほうが明るい PNG です。
        #expect(mask.value(at: CGPoint(x: 0.1, y: 0.1)) == 255)
        #expect(mask.value(at: CGPoint(x: 0.1, y: 0.9)) == 10)
    }

    // MARK: - 符号化

    @Test func 被覆率は値を変えずに往復する() throws {
        let mask = try #require(gradientMask())
        let data = try #require(codec.encode(mask))

        let restored = try #require(codec.decode(data, extent: mask.extent))

        #expect(restored.width == mask.width)
        #expect(restored.height == mask.height)
        #expect(restored.coverage == mask.coverage)
    }

    /// **1 チャンネルであることの確認。** 値が合っていても RGB で保存されていれば、
    /// 容量が 3 倍になり色空間の変換も挟まります。
    @Test func 保存したPNGは8bitの1チャンネルになる() throws {
        let mask = try #require(gradientMask())
        let data = try #require(codec.encode(mask))

        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(image.bitsPerComponent == 8)
        #expect(image.bitsPerPixel == 8)
        #expect(image.colorSpace?.model == .monochrome)
        #expect(image.alphaInfo == .none)
    }

    @Test func 覆う範囲は復号で渡した値になる() throws {
        let mask = try #require(gradientMask())
        let data = try #require(codec.encode(mask))
        let extent = CGRect(x: 0.2, y: 0.3, width: 0.5, height: 0.4)

        #expect(codec.decode(data, extent: extent)?.extent == extent)
    }

    @Test func 画像として読めないデータからは作れない() {
        #expect(codec.decode(Data([0x00, 0x01]), extent: CGRect(x: 0, y: 0, width: 1, height: 1)) == nil)
    }

    // MARK: - 保管庫とキャッシュ

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

    /// **元画像と同じ保管庫に置きます。** 保存の仕組みも掃除も使い回せます。
    @Test func 保管庫へ保存して読み戻せる() throws {
        try withTemporaryRepository { repository in
            let memo = Memo(title: "マスク")
            let mask = try #require(gradientMask())
            let assetID = try repository.save(try #require(codec.encode(mask)), in: memo.id)

            let store = CutoutMaskStore(repository: repository)
            let reference = try #require(makeReference(assetID, mask.extent))

            #expect(store.mask(for: reference, in: memo.id)?.coverage == mask.coverage)
            #expect(store.image(for: reference, in: memo.id) != nil)
        }
    }

    /// **同じ画像を別の範囲で参照したときの確認。**
    /// 鍵が `assetID` だけだと、先に読んだ範囲が返り続けます。
    @Test func 覆う範囲が違えば別のマスクを返す() throws {
        try withTemporaryRepository { repository in
            let memo = Memo(title: "範囲")
            let mask = try #require(gradientMask())
            let assetID = try repository.save(try #require(codec.encode(mask)), in: memo.id)
            let store = CutoutMaskStore(repository: repository)

            let wide = try #require(makeReference(assetID, CGRect(x: 0, y: 0, width: 1, height: 1)))
            let narrow = try #require(makeReference(assetID, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))

            #expect(store.mask(for: wide, in: memo.id)?.extent == wide.extent)
            #expect(store.mask(for: narrow, in: memo.id)?.extent == narrow.extent)
        }
    }

    /// アセットはメモに属します。**メモが違えば別物です。**
    @Test func メモが違えば別のマスクを返す() throws {
        try withTemporaryRepository { repository in
            let first = Memo(title: "1 つめ")
            let second = Memo(title: "2 つめ")
            let mask = try #require(gradientMask())
            let assetID = try repository.save(try #require(codec.encode(mask)), in: first.id)
            let store = CutoutMaskStore(repository: repository)
            let reference = try #require(makeReference(assetID, mask.extent))

            #expect(store.mask(for: reference, in: first.id) != nil)
            // 2 つめのメモには同じ ID のアセットがありません。
            #expect(store.mask(for: reference, in: second.id) == nil)
        }
    }

    @Test func 保存されていない参照はnilになる() throws {
        try withTemporaryRepository { repository in
            let store = CutoutMaskStore(repository: repository)
            let missing = try #require(makeReference(UUID(), CGRect(x: 0, y: 0, width: 1, height: 1)))

            #expect(store.mask(for: missing, in: Memo(title: "無し").id) == nil)
        }
    }

    // MARK: - 掃除

    @Test func 参照されているマスクは掃除で残る() throws {
        try withTemporaryRepository { repository in
            let memo = Memo(title: "掃除")
            let maskID = try repository.save(Data([0x89, 0x50, 0x4E, 0x47]), in: memo.id)
            let orphanID = try repository.save(Data([0x89, 0x50, 0x4E, 0x47]), in: memo.id)

            var updated = memo
            updated.canvas.elements = [
                CanvasElement(
                    kind: .imageCutout,
                    frame: .zero,
                    fillColor: .clear,
                    imageAssetID: UUID(),
                    cutoutMask: makeReference(maskID, CGRect(x: 0, y: 0, width: 1, height: 1))
                )
            ]

            try PruneImageAssetsUseCase(repository: repository)(for: updated)

            #expect(repository.data(for: maskID, in: memo.id) != nil)
            #expect(repository.data(for: orphanID, in: memo.id) == nil)
        }
    }

    /// 結合の構成元が持つマスクも残します。結合は解けるためです。
    @Test func 結合の構成元が持つマスクも残る() throws {
        try withTemporaryRepository { repository in
            let memo = Memo(title: "結合")
            let maskID = try repository.save(Data([0x89, 0x50, 0x4E, 0x47]), in: memo.id)
            let source = CanvasElement(
                kind: .imageCutout,
                frame: .zero,
                fillColor: .clear,
                cutoutMask: makeReference(maskID, CGRect(x: 0, y: 0, width: 1, height: 1))
            )

            var updated = memo
            updated.canvas.elements = [
                CanvasElement(
                    kind: .path,
                    frame: .zero,
                    fillColor: .paper,
                    unionSourceElements: [CanvasElementSnapshot(element: source)]
                )
            ]

            try PruneImageAssetsUseCase(repository: repository)(for: updated)

            #expect(repository.data(for: maskID, in: memo.id) != nil)
        }
    }

    // MARK: - 永続化

    @Test func マスクの参照が往復する() throws {
        let assetID = UUID()
        let element = CanvasElement(
            kind: .imageCutout,
            frame: CGRect(x: 0, y: 0, width: 10, height: 10),
            fillColor: .clear,
            cutoutMask: makeReference(assetID, CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        )

        let decoded = try JSONDecoder().decode(
            CanvasElement.self,
            from: try JSONEncoder().encode(element)
        )

        #expect(decoded.cutoutMask?.assetID == assetID)
        #expect(decoded.cutoutMask?.extent == element.cutoutMask?.extent)
    }

    /// 結合の構成元でも往復します。`CanvasElement` の表現を使い回しているためです。
    @Test func 結合の構成元でもマスクの参照が往復する() throws {
        let assetID = UUID()
        let source = CanvasElement(
            kind: .imageCutout,
            frame: .zero,
            fillColor: .clear,
            cutoutMask: makeReference(assetID, CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        )
        let element = CanvasElement(
            kind: .path,
            frame: .zero,
            fillColor: .paper,
            unionSourceElements: [CanvasElementSnapshot(element: source)]
        )

        let decoded = try JSONDecoder().decode(
            CanvasElement.self,
            from: try JSONEncoder().encode(element)
        )

        #expect(decoded.unionSourceElements.first?.cutoutMask?.assetID == assetID)
    }

    @Test func マスクを持たない要素にはキーが出ない() throws {
        let element = CanvasElement(kind: .rectangle, frame: .zero, fillColor: .paper)

        let json = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(element)) as? [String: Any]
        )

        #expect(json["cutoutMask"] == nil)
    }

    /// **手で書き換えられた JSON への備え。** 成立しない範囲は読み込みで弾きます。
    @Test func 成立しない範囲の参照は読み込めない() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "kind": "imageCutout",
          "x": 0, "y": 0, "width": 10, "height": 10,
          "fillColor": { "preset": "paper" },
          "cutoutMask": {
            "assetID": "\(UUID().uuidString)",
            "x": 0, "y": 0, "width": -1, "height": 0.5
          }
        }
        """

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CanvasElement.self, from: Data(json.utf8))
        }
    }

    @Test func 成立しない範囲の参照は作れない() {
        #expect(makeReference(UUID(), CGRect(x: 0, y: 0, width: 0, height: 0.5)) == nil)
        #expect(makeReference(UUID(), CGRect(x: 0, y: 0, width: .nan, height: 0.5)) == nil)
        #expect(makeReference(UUID(), CGRect(x: 0, y: 0, width: .infinity, height: 0.5)) == nil)
    }
}
