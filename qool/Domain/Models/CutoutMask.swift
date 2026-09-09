import CoreGraphics

/// 切り抜きのマスク。画素ごとの被覆率を持ちます。
///
/// **多角形と違い、縁の中間値を持てます。** アンチエイリアスした縁、ぼかし、
/// 髪の毛のような半透明が表現できるのはこの形式だけです。
///
/// **要素そのものには持たせません。** `CanvasElement` は値型で編集のたびに複製されるため、
/// 画素の配列を抱えると移動 1 回ごとに数 MB の複製が起きます。画像と同じく ID で参照します。
nonisolated struct CutoutMask: Equatable {
    /// マスクが覆う範囲。要素の枠を単位空間とした正規化座標です。
    ///
    /// **全面ではなく外接矩形に絞れます。** PSD がレイヤーマスクを矩形で持つのと同じ理由で、
    /// 使っていない領域の画素を抱えないためです。
    let extent: CGRect

    let width: Int
    let height: Int

    /// 被覆率。**行優先で、先頭が左上**です。
    let coverage: [UInt8]

    /// 画素数と配列の長さが合わなければ `nil`。
    init?(extent: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), width: Int, height: Int, coverage: [UInt8]) {
        guard width > 0, height > 0, coverage.count == width * height else {
            return nil
        }

        self.extent = extent
        self.width = width
        self.height = height
        self.coverage = coverage
    }

    /// 要素の枠を単位空間とした位置での被覆率。範囲の外は 0。
    ///
    /// **ヒットテストはここ 1 回の読み取りで済みます。** 多角形の交差数判定は
    /// 点の数に比例しますが、こちらは位置によらず一定です。
    func value(at point: CGPoint) -> UInt8 {
        guard extent.width > 0, extent.height > 0 else {
            return 0
        }

        let local = CGPoint(
            x: (point.x - extent.minX) / extent.width,
            y: (point.y - extent.minY) / extent.height
        )

        guard (0..<1).contains(local.x), (0..<1).contains(local.y) else {
            return 0
        }

        let column = min(width - 1, max(0, Int(local.x * CGFloat(width))))
        let row = min(height - 1, max(0, Int(local.y * CGFloat(height))))

        return coverage[row * width + column]
    }

    /// 被覆のある範囲まで切り詰めたマスク。全部が `threshold` 以下なら `nil`。
    ///
    /// **保存と描画の前に通します。** なぞりが画像の隅だけを囲んだ場合でも、
    /// 全面ぶんの画素を抱えずに済みます。
    func trimmed(threshold: UInt8 = 0) -> CutoutMask? {
        var minimumColumn = width
        var maximumColumn = -1
        var minimumRow = height
        var maximumRow = -1

        for row in 0..<height {
            for column in 0..<width where coverage[row * width + column] > threshold {
                minimumColumn = min(minimumColumn, column)
                maximumColumn = max(maximumColumn, column)
                minimumRow = min(minimumRow, row)
                maximumRow = max(maximumRow, row)
            }
        }

        guard maximumColumn >= minimumColumn, maximumRow >= minimumRow else {
            return nil
        }

        let trimmedWidth = maximumColumn - minimumColumn + 1
        let trimmedHeight = maximumRow - minimumRow + 1

        guard trimmedWidth != width || trimmedHeight != height else {
            return self
        }

        var trimmedCoverage: [UInt8] = []
        trimmedCoverage.reserveCapacity(trimmedWidth * trimmedHeight)

        for row in minimumRow...maximumRow {
            let start = row * width + minimumColumn
            trimmedCoverage.append(contentsOf: coverage[start..<(start + trimmedWidth)])
        }

        return CutoutMask(
            extent: CGRect(
                x: extent.minX + CGFloat(minimumColumn) / CGFloat(width) * extent.width,
                y: extent.minY + CGFloat(minimumRow) / CGFloat(height) * extent.height,
                width: CGFloat(trimmedWidth) / CGFloat(width) * extent.width,
                height: CGFloat(trimmedHeight) / CGFloat(height) * extent.height
            ),
            width: trimmedWidth,
            height: trimmedHeight,
            coverage: trimmedCoverage
        )
    }
}
