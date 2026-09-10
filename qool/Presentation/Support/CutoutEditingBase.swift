import CoreGraphics

/// 手直しの土台にどのマスクを使うか。
///
/// **一度落とした判断なので、独立させてテストできるようにしています。**
/// 既存のマスクを優先してしまうと、なぞり直したあとに矩形補正や手描きを選んでも
/// 新しい輪郭が捨てられ、古い形のまま適用されます。
nonisolated struct CutoutEditingBase {
    init() {}

    /// - Parameters:
    ///   - existing: 要素が既に持っているマスク。
    ///   - candidate: いま選ばれている候補のマスク。矩形補正と手描きは持ちません。
    ///   - hasRetraced: なぞり直したか。
    /// - Returns: 土台にするマスク。**どちらも無ければ `nil`**（呼び出し側が輪郭から起こします）。
    func mask(existing: CutoutMask?, candidate: CutoutMask?, hasRetraced: Bool) -> CutoutMask? {
        // **なぞり直したら既存は見ません。** 候補がマスクを持たないときは
        // `nil` を返し、その候補の輪郭から起こしてもらいます。
        hasRetraced ? candidate : existing
    }
}
