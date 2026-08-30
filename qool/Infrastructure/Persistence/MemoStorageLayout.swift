import Foundation

/// ディスク上の配置（[レイアウト案](../../../docs/architecture/persistence.md#レイアウト案)）。
///
/// ```text
/// <root>/memos/<memo-uuid>/memo.json
/// <root>/memos/<memo-uuid>/assets/<asset-uuid>.png
/// ```
///
/// メモ本体と画像アセットで別々のリポジトリがこの配置を使うため、
/// **パスの組み立てはここ 1 箇所に置きます。**
nonisolated struct MemoStorageLayout: Sendable {
    /// `~/Library/Application Support/qool/`。保存先はユーザーに選ばせずアプリが管理します
    /// （[ライブラリ管理型](../../../docs/architecture/persistence.md#どこに置くかは別の判断)）。
    static var defaultRootDirectory: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL.homeDirectory.appending(path: "Library/Application Support", directoryHint: .isDirectory)

        return applicationSupport.appending(path: "qool", directoryHint: .isDirectory)
    }

    static let memoFileName = "memo.json"

    let rootDirectory: URL

    init(rootDirectory: URL = MemoStorageLayout.defaultRootDirectory) {
        self.rootDirectory = rootDirectory
    }

    var memosDirectory: URL {
        rootDirectory.appending(path: "memos", directoryHint: .isDirectory)
    }

    func memoDirectory(for memoID: Memo.ID) -> URL {
        memosDirectory.appending(path: memoID.uuidString, directoryHint: .isDirectory)
    }

    func memoFile(for memoID: Memo.ID) -> URL {
        memoDirectory(for: memoID).appending(path: Self.memoFileName)
    }

    func assetsDirectory(for memoID: Memo.ID) -> URL {
        memoDirectory(for: memoID).appending(path: "assets", directoryHint: .isDirectory)
    }

    /// 拡張子を `.png` に固定しています。Finder でそのまま開けることが
    /// [方式 A](../../../docs/architecture/persistence.md) の利点のひとつだからです。
    func assetFile(_ assetID: UUID, in memoID: Memo.ID) -> URL {
        assetsDirectory(for: memoID).appending(path: "\(assetID.uuidString).png")
    }
}
