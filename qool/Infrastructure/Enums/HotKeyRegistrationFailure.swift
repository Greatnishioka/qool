import Foundation

/// ホットキーを登録できなかった理由。
///
/// **他のアプリが同じ組み合わせを先に取っている場合が主です。**
/// 画面には「そのキーは使えません」と伝えて、別のキーを選ばせる必要があります。
nonisolated enum HotKeyRegistrationFailure: LocalizedError {
    /// OS が登録を拒んだ。`status` は Carbon が返した値。
    case rejectedBySystem(status: Int)
    case handlerUnavailable(status: Int)

    var errorDescription: String? {
        switch self {
        case .rejectedBySystem:
            return "そのキーの組み合わせは、ほかのアプリが使っています"
        case .handlerUnavailable:
            return "キー入力を受け取れませんでした"
        }
    }
}
