import Foundation
import os

/// 画像アセットをメモのディレクトリ配下へ保存するリポジトリ。
///
/// 同じ写真から複数のメモを作ると元画像は重複しますが、**MVP では許容します**
/// （[同一画像の重複](../../../docs/architecture/persistence.md#同一画像の重複)）。
/// 共有すると削除時に参照カウントが要り、複雑さのほうが勝ちます。
///
/// `@unchecked Sendable` の根拠: 格納プロパティはすべて `let` で、
/// `FileManager` は Apple がスレッド安全と明記している範囲でのみ使っています。
nonisolated final class FileImageAssetRepositoryInfrastructure: ImageAssetRepositoryProtocol, @unchecked Sendable {
    private let layout: MemoStorageLayout
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "dev.ayato.qool", category: "persistence")

    /// - Parameter rootDirectory: 保存先の親。テストでは一時ディレクトリを渡します。
    init(
        rootDirectory: URL = MemoStorageLayout.defaultRootDirectory,
        fileManager: FileManager = .default
    ) {
        self.layout = MemoStorageLayout(rootDirectory: rootDirectory)
        self.fileManager = fileManager
    }

    /// 読めなければ `nil`。**投げません。**
    /// 画像 1 枚が壊れていても、メモそのものは開けるべきだからです。
    func data(for id: UUID, in memoID: Memo.ID) -> Data? {
        let fileURL = layout.assetFile(id, in: memoID)

        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return nil
        }

        do {
            return try Data(contentsOf: fileURL)
        } catch {
            logger.error(
                """
                画像アセットの読み込みに失敗しました \
                id=\(id, privacy: .public): \(error.localizedDescription, privacy: .public)
                """
            )
            return nil
        }
    }

    @discardableResult
    func save(_ data: Data, in memoID: Memo.ID) throws -> UUID {
        let id = UUID()
        let directory = layout.assetsDirectory(for: memoID)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // アトミック書き込み。書き込み中のクラッシュで半端な画像が残るのを防ぎます。
        try data.write(to: layout.assetFile(id, in: memoID), options: .atomic)

        return id
    }

    func delete(id: UUID, in memoID: Memo.ID) throws {
        let fileURL = layout.assetFile(id, in: memoID)

        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
    }
}
