/// 切り抜きの手直しの履歴。
///
/// **スナップショット方式です。** 操作を積んで再生する形も検討しましたが、
/// 合成 1 手が 11〜19ms かかるため（実測）、20 手の再生で 0.2〜0.4 秒固まります。
/// 戻すたびに待たされる道具にはできません。編集後の輪郭をそのまま持てば差し替え 1 回で済みます。
///
/// **ディスクには残しません。** `Memo` は値型で編集のたびに丸ごとコピー・比較されるため、
/// ここに履歴を入れると 1 ストロークごとに全履歴のコピーが走ります
/// （画像を `Memo` に入れないのと同じ理由）。シートを閉じた時点で捨てます。
nonisolated struct ContourEditHistory: Equatable {
    static let defaultLimit = 100
    static let limitRange = 1...500

    /// 履歴が抱えてよい合計の大きさ。
    ///
    /// **手数だけでは縛れません。** 込み入った形だと 1 件 45KB になり（実測）、
    /// 500 件で 22MB を超えます。形の複雑さは手数から読めないので、両方で打ち切ります。
    static let maximumTotalBytes = 32 * 1024 * 1024

    /// `NormalizedPoint` 1 点あたりの見積もり（`Double` 2 つ）。
    private static let bytesPerPoint = 16

    private struct Snapshot: Equatable {
        let contours: [CanvasPathContour]
        let byteSize: Int

        init(_ contours: [CanvasPathContour]) {
            self.contours = contours
            byteSize = contours.reduce(0) { $0 + $1.points.count } * ContourEditHistory.bytesPerPoint
        }
    }

    private(set) var current: [CanvasPathContour]
    private(set) var limit: Int

    private var pastStates: [Snapshot] = []
    private var futureStates: [Snapshot] = []
    /// 積み直すたびに数え直すと、点数に比例した走査が毎回入ります。増減だけを追います。
    private var totalBytes = 0

    init(_ contours: [CanvasPathContour], limit: Int = ContourEditHistory.defaultLimit) {
        current = contours
        self.limit = Self.clamped(limit)
    }

    var canUndo: Bool { !pastStates.isEmpty }
    var canRedo: Bool { !futureStates.isEmpty }
    var undoCount: Int { pastStates.count }
    var estimatedBytes: Int { totalBytes }

    /// 編集後の輪郭を積む。
    ///
    /// **変化がなければ何もしません。** 同じ結果で埋まると、戻せる手数が実質減ります。
    mutating func record(_ contours: [CanvasPathContour]) {
        guard contours != current else {
            return
        }

        append(Snapshot(current), to: \.pastStates)
        // 新しい枝を作ったので、やり直せる先は捨てます。
        totalBytes -= futureStates.reduce(0) { $0 + $1.byteSize }
        futureStates.removeAll()
        current = contours
        trim()
    }

    mutating func undo() {
        guard let previous = pastStates.popLast() else {
            return
        }

        totalBytes -= previous.byteSize
        append(Snapshot(current), to: \.futureStates)
        current = previous.contours
    }

    mutating func redo() {
        guard let next = futureStates.popLast() else {
            return
        }

        totalBytes -= next.byteSize
        append(Snapshot(current), to: \.pastStates)
        current = next.contours
    }

    /// 上限を変える。**その場ではみ出した分を捨てます。**
    /// 下げた直後だけ以前の上限のまま戻せる、という食い違いを避けるためです。
    mutating func updateLimit(_ newLimit: Int) {
        limit = Self.clamped(newLimit)
        trim()
    }

    private mutating func append(_ snapshot: Snapshot, to keyPath: WritableKeyPath<ContourEditHistory, [Snapshot]>) {
        self[keyPath: keyPath].append(snapshot)
        totalBytes += snapshot.byteSize
    }

    /// 古いほうから捨てます。**やり直せる先は残します。**
    /// 戻した直後にやり直せなくなると、戻す操作そのものが怖くなります。
    private mutating func trim() {
        while pastStates.count > limit || (totalBytes > Self.maximumTotalBytes && !pastStates.isEmpty) {
            totalBytes -= pastStates.removeFirst().byteSize
        }
    }

    private static func clamped(_ limit: Int) -> Int {
        min(max(limit, limitRange.lowerBound), limitRange.upperBound)
    }
}
