import CoreGraphics
import Foundation

/// デスクトップに貼った位置を書き換える。`nil` を渡すとはがします。
///
/// **`updatedAt` を触らないのが `SaveMemoUseCase` との違いです。**
/// ウィンドウをドラッグしただけで一覧の並び（更新日時の降順）が変わるのを避けます。
nonisolated struct UpdateFloatingOriginUseCase {
    let repository: any MemoRepositoryProtocol

    @discardableResult
    func callAsFunction(_ memo: Memo, to origin: CGPoint?) async throws -> Memo {
        var updatedMemo = memo
        updatedMemo.floatingOrigin = origin
        try await repository.save(updatedMemo)

        return updatedMemo
    }
}
