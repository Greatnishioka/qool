import Foundation
import os

/// メモをファイルとして保存するリポジトリ（[方式 A](../../../docs/architecture/persistence.md)）。
///
/// 1 メモ = 1 ディレクトリにしているため、**壊れても被害はそのメモだけ**に留まります。
/// `@unchecked Sendable` の根拠: 格納プロパティはすべて `let` で、
/// `JSONEncoder` / `JSONDecoder` は呼び出しごとに作るため共有していません。
nonisolated final class FileMemoRepositoryInfrastructure: MemoRepositoryProtocol, @unchecked Sendable {
    /// 保存フォーマットの版。互換性を壊す変更を入れるときに上げます。
    static let schemaVersion = 1

    /// `memo.json` の中身。`Memo` を直接書かず版を添えて包みます。
    private struct StoredMemo: Codable {
        var schemaVersion: Int
        var memo: Memo
    }

    private enum FileName {
        static let memo = "memo.json"
        static let memosDirectory = "memos"
        static let assetsDirectory = "assets"
    }

    private let rootDirectory: URL
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "dev.ayato.qool", category: "persistence")

    /// 日時は ISO8601 の文字列。標準の `.iso8601` 戦略は秒までしか持たず、
    /// 短時間に何度も保存されるメモでは更新順が決まらないため、ミリ秒まで残します。
    /// `ISO8601DateFormatter` は `Sendable` ではないため、値型の `FormatStyle` を使います。
    private static let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // 人が読める形にする（壊れたときに手で直せる）。
        // sortedKeys は差分を安定させ、Git や Time Machine と併用しやすくします。
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(FileMemoRepositoryInfrastructure.dateFormat.format(date))
        }
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)

            do {
                return try FileMemoRepositoryInfrastructure.dateFormat.parse(text)
            } catch {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "ISO8601 の日時として読めません: \(text)"
                )
            }
        }
        return decoder
    }

    /// - Parameter rootDirectory: 保存先の親。テストでは一時ディレクトリを渡します。
    init(
        rootDirectory: URL = FileMemoRepositoryInfrastructure.defaultRootDirectory,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    /// `~/Library/Application Support/qool/`。保存先はユーザーに選ばせずアプリが管理します
    /// （[ライブラリ管理型](../../../docs/architecture/persistence.md#どこに置くかは別の判断)）。
    static var defaultRootDirectory: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL.homeDirectory.appending(path: "Library/Application Support", directoryHint: .isDirectory)

        return applicationSupport.appending(path: "qool", directoryHint: .isDirectory)
    }

    // MARK: - MemoRepositoryProtocol

    func loadMemos() throws -> [Memo] {
        let memosDirectory = memosDirectory

        // 一度も保存していなければディレクトリがありません。これは失敗ではありません。
        guard fileManager.fileExists(atPath: memosDirectory.path(percentEncoded: false)) else {
            return []
        }

        // ここで投げるのは「一覧そのものが読めない」場合だけです。
        // 個々のメモの失敗は loadMemo が nil を返して読み飛ばします。
        let directories = try fileManager.contentsOfDirectory(
            at: memosDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return directories
            .compactMap(loadMemo(inDirectory:))
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// `@concurrent` がないと `SWIFT_APPROACHABLE_CONCURRENCY` の既定により
    /// **呼び出し元（MainActor）の上で動いてしまい、非同期にした意味がありません。**
    @concurrent
    func save(_ memo: Memo) async throws {
        let directory = memoDirectory(for: memo.id)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(StoredMemo(schemaVersion: Self.schemaVersion, memo: memo))
        // アトミック書き込み。編集のたびに保存が走るため、
        // 書き込み中のクラッシュで memo.json が半端な状態になるのを防ぎます。
        try data.write(to: directory.appending(path: FileName.memo), options: .atomic)
    }

    @concurrent
    func delete(id: Memo.ID) async throws {
        let directory = memoDirectory(for: id)

        // 存在しないものの削除は成功として扱います。
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return
        }

        try fileManager.removeItem(at: directory)
    }

    // MARK: - 配置

    private var memosDirectory: URL {
        rootDirectory.appending(path: FileName.memosDirectory, directoryHint: .isDirectory)
    }

    private func memoDirectory(for id: Memo.ID) -> URL {
        memosDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// 画像アセットの置き場所。`ImageAssetRepositoryProtocol` の実装から使う想定です。
    func assetsDirectory(for id: Memo.ID) -> URL {
        memoDirectory(for: id).appending(path: FileName.assetsDirectory, directoryHint: .isDirectory)
    }

    // MARK: - 読み込み

    /// 1 メモ分の読み込み。失敗しても `nil` を返すだけで、他のメモには影響させません。
    private func loadMemo(inDirectory directory: URL) -> Memo? {
        let isDirectory = (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
        guard isDirectory == true else {
            return nil
        }

        // ディレクトリ名はメモの ID。Finder で複製されると同じ ID のメモが 2 件読み込まれ、
        // `List` の識別子が重複するため、名前が ID として読めることを先に要求します。
        guard let directoryID = UUID(uuidString: directory.lastPathComponent) else {
            return nil
        }

        let fileURL = directory.appending(path: FileName.memo)

        // `save` はディレクトリを作ってから書き込むため、その間に終了すると
        // `memo.json` のないディレクトリが残ります。静かに読み飛ばします。
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let stored = try decoder.decode(StoredMemo.self, from: data)

            guard stored.schemaVersion <= Self.schemaVersion else {
                // 新しい版で書かれたファイルを古いアプリが壊さないよう、読まずに残します。
                logger.error(
                    """
                    未知のスキーマ版のため読み飛ばしました \
                    path=\(directory.lastPathComponent, privacy: .public) \
                    version=\(stored.schemaVersion, privacy: .public)
                    """
                )
                return nil
            }

            // 複製されたディレクトリは名前と中身の ID がずれます。読み込むと同じ ID のメモが
            // 二重に現れ、保存は正規のディレクトリへ向かうため複製側は古いまま残り続けます。
            guard stored.memo.id == directoryID else {
                logger.error(
                    """
                    ディレクトリ名とメモ ID が一致しないため読み飛ばしました \
                    path=\(directory.lastPathComponent, privacy: .public) \
                    id=\(stored.memo.id, privacy: .public)
                    """
                )
                return nil
            }

            return stored.memo
        } catch {
            logger.error(
                """
                メモの読み込みに失敗しました \
                path=\(directory.lastPathComponent, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """
            )
            return nil
        }
    }
}
