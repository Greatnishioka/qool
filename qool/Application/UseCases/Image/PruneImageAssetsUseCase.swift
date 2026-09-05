import Foundation

/// メモが参照していない画像を消す。
///
/// **結合の元要素が持つ画像も残します。** 結合は解けるので、
/// そのときに戻る要素の画像を消してしまうと、解いた先に絵がありません。
nonisolated struct PruneImageAssetsUseCase {
    let repository: any ImageAssetRepositoryProtocol

    func callAsFunction(for memo: Memo) throws {
        try repository.deleteAssets(in: memo.id, keeping: usedAssetIDs(in: memo.canvas))
    }

    private func usedAssetIDs(in canvas: Canvas) -> Set<UUID> {
        var usedIDs: Set<UUID> = []

        for element in canvas.elements {
            usedIDs.formUnion([element.imageAssetID].compactMap(\.self))
            usedIDs.formUnion(element.unionSourceElements.compactMap(\.imageAssetID))
        }

        return usedIDs
    }
}
