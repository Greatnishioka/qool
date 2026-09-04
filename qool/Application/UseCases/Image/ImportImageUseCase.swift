import Foundation

/// 画像をメモのアセットとして保存し、割り当てた ID を返す。
///
/// **バイト列は PNG である必要があります**（保存先の拡張子が固定のため）。
/// `NSImage` からの変換は Presentation の責務です。
nonisolated struct ImportImageUseCase {
    let repository: any ImageAssetRepositoryProtocol

    func callAsFunction(_ data: Data, in memoID: Memo.ID) throws -> UUID {
        try repository.save(data, in: memoID)
    }
}
