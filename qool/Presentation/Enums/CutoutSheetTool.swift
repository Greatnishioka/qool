/// 切り抜きシートの道具。
///
/// **投げ縄を足す / 消すで分けています。** 1 つにして切り替えを別に置くと、
/// 押す前に今どちらなのかを確かめる必要が出ます。道具として並べれば見れば分かります。
nonisolated enum CutoutSheetTool: String, CaseIterable, Identifiable, Hashable {
    /// 外周をなぞって輪郭を引き直す。
    case trace
    case pen
    case eraser
    case lassoAdd
    case lassoSubtract
    /// 押した場所から色の近い範囲を広げて足す / 引く。
    case regionAdd
    case regionSubtract

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .trace: return "なぞる"
        case .pen: return "ペン"
        case .eraser: return "消しゴム"
        case .lassoAdd: return "囲んで足す"
        case .lassoSubtract: return "囲んで消す"
        case .regionAdd: return "領域を足す"
        case .regionSubtract: return "領域を消す"
        }
    }

    var systemImage: String {
        switch self {
        case .trace: return "scribble"
        case .pen: return "paintbrush.pointed"
        case .eraser: return "eraser"
        case .lassoAdd: return "lasso.badge.sparkles"
        case .lassoSubtract: return "lasso"
        case .regionAdd: return "wand.and.sparkles"
        case .regionSubtract: return "wand.and.rays"
        }
    }

    /// なぞりの太さが効くか。投げ縄と領域は形そのものを使うため効きません。
    var usesBrushSize: Bool {
        self == .pen || self == .eraser
    }

    /// 押した場所から領域を広げる道具か。**なぞりではなく 1 回のクリックで効きます。**
    var fillsRegion: Bool {
        self == .regionAdd || self == .regionSubtract
    }

    /// 囲んだ内側を塗る道具か。
    var enclosesArea: Bool {
        self == .lassoAdd || self == .lassoSubtract
    }

    /// 輪郭に足すか引くか。`trace` は手直しではないので持ちません。
    var editMode: ContourEditMode? {
        switch self {
        case .trace: return nil
        case .pen, .lassoAdd, .regionAdd: return .add
        case .eraser, .lassoSubtract, .regionSubtract: return .subtract
        }
    }
}
