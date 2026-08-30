import Foundation
import Testing
@testable import qool

/// [FileImageAssetRepositoryInfrastructure](../qool/Infrastructure/Persistence/FileImageAssetRepositoryInfrastructure.swift) の検証。
/// 実際のファイルシステムを使い、テストごとに一時ディレクトリを作って捨てます。
struct FileImageAssetRepositoryInfrastructureTests {
    private func withTemporaryRepository(
        _ body: (FileImageAssetRepositoryInfrastructure, URL) throws -> Void
    ) throws {
        let root = URL.temporaryDirectory.appending(
            path: "qool-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try body(FileImageAssetRepositoryInfrastructure(rootDirectory: root), root)
    }

    private let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    @Test
    func 保存したデータを読み出せる() throws {
        try withTemporaryRepository { repository, _ in
            let memoID = UUID()
            let assetID = try repository.save(imageData, in: memoID)

            #expect(repository.data(for: assetID, in: memoID) == imageData)
        }
    }

    @Test
    func メモのディレクトリ配下に置かれる() throws {
        try withTemporaryRepository { repository, root in
            let memoID = UUID()
            let assetID = try repository.save(imageData, in: memoID)

            let expectedURL = root
                .appending(path: "memos", directoryHint: .isDirectory)
                .appending(path: memoID.uuidString, directoryHint: .isDirectory)
                .appending(path: "assets", directoryHint: .isDirectory)
                .appending(path: "\(assetID.uuidString).png")

            #expect(FileManager.default.fileExists(atPath: expectedURL.path(percentEncoded: false)))
        }
    }

    /// アセットはメモに属します。同じ ID でも別のメモからは見えません。
    @Test
    func 別のメモからは読めない() throws {
        try withTemporaryRepository { repository, _ in
            let memoID = UUID()
            let assetID = try repository.save(imageData, in: memoID)

            #expect(repository.data(for: assetID, in: UUID()) == nil)
        }
    }

    @Test
    func 保存していないIDはnilを返す() throws {
        try withTemporaryRepository { repository, _ in
            #expect(repository.data(for: UUID(), in: UUID()) == nil)
        }
    }

    @Test
    func 保存するたびに別のIDが割り当てられる() throws {
        try withTemporaryRepository { repository, _ in
            let memoID = UUID()
            let firstID = try repository.save(imageData, in: memoID)
            let secondID = try repository.save(imageData, in: memoID)

            #expect(firstID != secondID)
            #expect(repository.data(for: firstID, in: memoID) == imageData)
            #expect(repository.data(for: secondID, in: memoID) == imageData)
        }
    }

    @Test
    func 削除するとファイルごと消える() throws {
        try withTemporaryRepository { repository, _ in
            let memoID = UUID()
            let assetID = try repository.save(imageData, in: memoID)

            try repository.delete(id: assetID, in: memoID)

            #expect(repository.data(for: assetID, in: memoID) == nil)
        }
    }

    /// 存在しないものの削除は成功として扱います。呼び出し元が事前確認をしなくて済むためです。
    @Test
    func 存在しないIDの削除は投げない() throws {
        try withTemporaryRepository { repository, _ in
            #expect(throws: Never.self) {
                try repository.delete(id: UUID(), in: UUID())
            }
        }
    }

    /// メモを消せばアセットも一緒に消えます。ディレクトリを共有しているためです。
    @Test
    func メモのディレクトリを消すとアセットも消える() throws {
        try withTemporaryRepository { repository, root in
            let memoID = UUID()
            let assetID = try repository.save(imageData, in: memoID)

            try FileManager.default.removeItem(
                at: root
                    .appending(path: "memos", directoryHint: .isDirectory)
                    .appending(path: memoID.uuidString, directoryHint: .isDirectory)
            )

            #expect(repository.data(for: assetID, in: memoID) == nil)
        }
    }
}
