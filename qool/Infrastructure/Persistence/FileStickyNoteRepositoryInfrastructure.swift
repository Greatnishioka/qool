import Foundation
import OSLog

/// 付箋をディスクへ置く。
///
/// **1 件 1 ファイルです。** 付箋は自分の画像を持たないので、
/// メモのようにディレクトリを切る必要がありません
/// （[MemoStorageLayout](MemoStorageLayout.swift)）。
///
/// 読み書きの作法は [FileMemoRepositoryInfrastructure](FileMemoRepositoryInfrastructure.swift)
/// に合わせています。**壊れた 1 件で一覧全体を落としません。**
nonisolated final class FileStickyNoteRepositoryInfrastructure: StickyNoteRepositoryProtocol, @unchecked Sendable {
    /// 保存フォーマットの版。互換性を壊す変更を入れるときに上げます。
    static let schemaVersion = 1

    /// 付箋のファイルの中身。`StickyNote` を直接書かず版を添えて包みます。
    private struct StoredStickyNote: Codable {
        var schemaVersion: Int
        var note: StickyNote
    }

    private let layout: MemoStorageLayout
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "dev.ayato.qool", category: "persistence")

    /// メモ側と同じ形式で書きます。**秒までだと更新順が決まらない**ので、ミリ秒まで残します。
    private static let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(FileStickyNoteRepositoryInfrastructure.dateFormat.format(date))
        }

        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)

            do {
                return try FileStickyNoteRepositoryInfrastructure.dateFormat.parse(text)
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
        rootDirectory: URL = MemoStorageLayout.defaultRootDirectory,
        fileManager: FileManager = .default
    ) {
        self.layout = MemoStorageLayout(rootDirectory: rootDirectory)
        self.fileManager = fileManager
    }

    // MARK: - StickyNoteRepositoryProtocol

    func loadStickyNotes() throws -> [StickyNote] {
        let directory = layout.stickyNotesDirectory

        // 一度も出していなければディレクトリがありません。これは失敗ではありません。
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return []
        }

        // ここで投げるのは「一覧そのものが読めない」場合だけです。
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap(loadStickyNote(at:))
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// `@concurrent` がないと `SWIFT_APPROACHABLE_CONCURRENCY` の既定により
    /// **呼び出し元（MainActor）の上で動いてしまい、非同期にした意味がありません。**
    @concurrent
    func save(_ note: StickyNote) async throws {
        try fileManager.createDirectory(
            at: layout.stickyNotesDirectory,
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(
            StoredStickyNote(schemaVersion: Self.schemaVersion, note: note)
        )
        // アトミック書き込み。本文は打つたびに保存されるため、
        // 書き込み中のクラッシュで半端な状態になるのを防ぎます。
        try data.write(to: layout.stickyNoteFile(for: note.id), options: .atomic)
    }

    @concurrent
    func delete(id: StickyNote.ID) async throws {
        let file = layout.stickyNoteFile(for: id)

        // 存在しないものの削除は成功として扱います。
        guard fileManager.fileExists(atPath: file.path(percentEncoded: false)) else {
            return
        }

        try fileManager.removeItem(at: file)
    }

    // MARK: - 読み込み

    /// **壊れた 1 件は静かに読み飛ばします。** 一覧全体が開けなくなるほうが困ります。
    private func loadStickyNote(at fileURL: URL) -> StickyNote? {
        guard let fileID = UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let stored = try decoder.decode(StoredStickyNote.self, from: data)

            // **ファイル名と中身の id が食い違うものは信じません。**
            // 手でコピーしたファイルが混ざると、削除が効かない付箋ができます。
            guard stored.note.id == fileID else {
                logger.error("付箋の id がファイル名と一致しません: \(fileURL.lastPathComponent, privacy: .public)")

                return nil
            }

            return stored.note
        } catch {
            logger.error("付箋を読めませんでした: \(fileURL.lastPathComponent, privacy: .public)")

            return nil
        }
    }
}
