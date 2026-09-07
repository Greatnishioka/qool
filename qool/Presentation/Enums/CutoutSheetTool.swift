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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .trace: return "なぞる"
        case .pen: return "ペン"
        case .eraser: return "消しゴム"
        case .lassoAdd: return "囲んで足す"
        case .lassoSubtract: return "囲んで消す"
        }
    }

    var systemImage: String {
        switch self {
        case .trace: return "scribble"
        case .pen: return "paintbrush.pointed"
        case .eraser: return "eraser"
        case .lassoAdd: return "lasso.badge.sparkles"
        case .lassoSubtract: return "lasso"
        }
    }

    /// なぞりの太さが効くか。投げ縄は囲んだ形そのものを使うため効きません。
    var usesBrushSize: Bool {
        self == .pen || self == .eraser
    }

    /// 輪郭に足すか引くか。`trace` は手直しではないので持ちません。
    var editMode: ContourEditMode? {
        switch self {
        case .trace: return nil
        case .pen, .lassoAdd: return .add
        case .eraser, .lassoSubtract: return .subtract
        }
    }
}
