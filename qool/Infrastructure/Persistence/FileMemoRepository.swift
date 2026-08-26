import Foundation
import os

/// メモをファイルとして保存するリポジトリ。
///
/// [永続化方針](../../../docs/architecture/persistence.md)で決まった方式 A（ファイル + JSON）の実装です。
///
/// ```text
/// ~/Library/Application Support/qool/
///   memos/
///     <memo-uuid>/
///       memo.json
///       assets/          （画像アセット。ImageAssetRepository が使う）
/// ```
///
/// 1 メモ = 1 ディレクトリにしているため、**壊れても被害はそのメモだけ**に留まります。
/// 読み込みに失敗したメモは読み飛ばし、残りを返します。
final class FileMemoRepository: MemoRepository {
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

    /// 日時は ISO8601 の文字列で持ちます。数値より読みやすく、手で直せます。
    ///
    /// 標準の `.iso8601` 戦略は秒までしか持たないため、ミリ秒まで残す指定にしています。
    /// メモは短時間に何度も保存されるので、秒単位だと更新順が決まりません。
    /// なお `Date` は秒の実数値なので、**ミリ秒より下は往復で丸められます。**
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // 人が読める形にする（方式 A の利点。壊れたときに手で直せる）。
        // sortedKeys は差分を安定させ、Git や Time Machine と併用しやすくします。
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(FileMemoRepository.dateFormatter.string(from: date))
        }
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)

            guard let date = FileMemoRepository.dateFormatter.date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "ISO8601 の日時として読めません: \(text)"
                )
            }

            return date
        }
        return decoder
    }()

    /// - Parameter rootDirectory: 保存先の親。テストでは一時ディレクトリを渡します。
    init(
        rootDirectory: URL = FileMemoRepository.defaultRootDirectory,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    /// `~/Library/Application Support/qool/`
    ///
    /// ホットキーで呼び出して使うアプリなので、保存先はユーザーに選ばせず
    /// アプリが管理します（[ライブラリ管理型](../../../docs/architecture/persistence.md#どこに置くかは別の判断)）。
    static var defaultRootDirectory: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL.homeDirectory.appending(path: "Library/Application Support", directoryHint: .isDirectory)

        return applicationSupport.appending(path: "qool", directoryHint: .isDirectory)
    }

    // MARK: - MemoRepository

    func loadMemos() -> [Memo] {
        let memosDirectory = memosDirectory

        guard fileManager.fileExists(atPath: memosDirectory.path(percentEncoded: false)) else {
            return []
        }

        let directories: [URL]
        do {
            directories = try fileManager.contentsOfDirectory(
                at: memosDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            logger.error("メモ一覧の読み込みに失敗しました: \(error.localizedDescription, privacy: .public)")
            return []
        }

        return directories
            .compactMap(loadMemo(inDirectory:))
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ memo: Memo) {
        let directory = memoDirectory(for: memo.id)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(StoredMemo(schemaVersion: Self.schemaVersion, memo: memo))
            // アトミック書き込み。編集のたびに保存が走るため、
            // 書き込み中のクラッシュで memo.json が半端な状態になるのを防ぎます。
            try data.write(to: directory.appending(path: FileName.memo), options: .atomic)
        } catch {
            logger.error(
                "メモの保存に失敗しました id=\(memo.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func delete(id: Memo.ID) {
        let directory = memoDirectory(for: id)

        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return
        }

        do {
            try fileManager.removeItem(at: directory)
        } catch {
            logger.error(
                "メモの削除に失敗しました id=\(id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - 配置

    private var memosDirectory: URL {
        rootDirectory.appending(path: FileName.memosDirectory, directoryHint: .isDirectory)
    }

    private func memoDirectory(for id: Memo.ID) -> URL {
        memosDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// 画像アセットの置き場所。`ImageAssetRepository` の実装から使う想定です。
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

        let fileURL = directory.appending(path: FileName.memo)

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
