import CoreGraphics

/// マスクの手直しの履歴。
///
/// **変更のあった矩形だけを持ちます。** マスクを丸ごと手数ぶん積むと、
/// 500 手で数 GB になります。1 手の大きさがなぞった範囲に収まるので、
/// 上限を大きくしても現実的です（[設計](https://github.com/Greatnishioka/qool/issues/12)）。
nonisolated struct CutoutMaskEditHistory {
    /// 戻せる手数の範囲。設定で変えられます。
    static let limitRange = ContourEditHistory.limitRange

    /// 1 手ぶんの差分。**戻す用と進む用の両方を持ちます。**
    /// 片方だけだと、戻したあとにやり直せません。
    private struct Patch {
        let column: Int
        let row: Int
        let width: Int
        let height: Int
        let before: [UInt8]
        let after: [UInt8]
    }

    private(set) var current: CutoutMask

    private var patches: [Patch] = []
    /// 次に戻すときに使う添字。ここより後ろはやり直しで使います。
    private var position = 0
    private let limit: Int

    init(_ mask: CutoutMask, limit: Int) {
        self.current = mask
        self.limit = min(max(limit, Self.limitRange.lowerBound), Self.limitRange.upperBound)
    }

    var canUndo: Bool { position > 0 }
    var canRedo: Bool { position < patches.count }

    /// 手直しの結果を積む。**格子が違うものは受け付けません。**
    mutating func record(_ mask: CutoutMask) {
        guard mask.width == current.width, mask.height == current.height else {
            return
        }

        guard let patch = makePatch(from: current, to: mask) else {
            // 何も変わっていなければ積みません。押し戻す手数を無駄に消費しません。
            return
        }

        // やり直せる分は捨てます。枝分かれを持つと、どちらが正か決められません。
        patches.removeSubrange(position...)
        patches.append(patch)

        if patches.count > limit {
            patches.removeFirst(patches.count - limit)
        }

        position = patches.count
        current = mask
    }

    mutating func undo() {
        guard canUndo else {
            return
        }

        position -= 1
        current = applied(patches[position], reversed: true)
    }

    mutating func redo() {
        guard canRedo else {
            return
        }

        current = applied(patches[position], reversed: false)
        position += 1
    }

    // MARK: - 差分

    /// 変わった画素を囲む矩形を探し、その範囲だけを控える。
    private func makePatch(from old: CutoutMask, to new: CutoutMask) -> Patch? {
        var minimumColumn = old.width
        var maximumColumn = -1
        var minimumRow = old.height
        var maximumRow = -1

        for row in 0..<old.height {
            let offset = row * old.width
            var first = -1
            var last = -1

            for column in 0..<old.width where old.coverage[offset + column] != new.coverage[offset + column] {
                if first < 0 {
                    first = column
                }

                last = column
            }

            guard first >= 0 else {
                continue
            }

            minimumColumn = min(minimumColumn, first)
            maximumColumn = max(maximumColumn, last)
            minimumRow = min(minimumRow, row)
            maximumRow = row
        }

        guard maximumColumn >= minimumColumn, maximumRow >= minimumRow else {
            return nil
        }

        let width = maximumColumn - minimumColumn + 1
        let height = maximumRow - minimumRow + 1
        var before: [UInt8] = []
        var after: [UInt8] = []
        before.reserveCapacity(width * height)
        after.reserveCapacity(width * height)

        for row in minimumRow...maximumRow {
            let start = row * old.width + minimumColumn
            before.append(contentsOf: old.coverage[start..<(start + width)])
            after.append(contentsOf: new.coverage[start..<(start + width)])
        }

        return Patch(
            column: minimumColumn,
            row: minimumRow,
            width: width,
            height: height,
            before: before,
            after: after
        )
    }

    private func applied(_ patch: Patch, reversed: Bool) -> CutoutMask {
        var coverage = current.coverage
        let values = reversed ? patch.before : patch.after

        for row in 0..<patch.height {
            let destination = (patch.row + row) * current.width + patch.column
            let source = row * patch.width
            coverage.replaceSubrange(
                destination..<(destination + patch.width),
                with: values[source..<(source + patch.width)]
            )
        }

        return CutoutMask(
            extent: current.extent,
            width: current.width,
            height: current.height,
            coverage: coverage
        ) ?? current
    }
}
