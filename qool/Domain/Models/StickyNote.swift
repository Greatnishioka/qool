import CoreGraphics
import Foundation

/// 雛形から出した付箋。机の上に置く 1 枚です。
///
/// **形とレイアウトは持ちません。** 雛形を参照し、**本文だけ**を自分で持ちます
/// （[#29](https://github.com/Greatnishioka/qool/issues/29)）。
///
/// **複製ではなく参照にしています。** 画像アセットは雛形の id で名前空間が切られているため、
/// 複製にすると付箋ごとに画像と切り抜きマスクを全部コピーすることになります。
/// 参照なら、アセットまわりには一切手を入れずに済みます。
///
/// 副作用として、**雛形を直すと既に出した付箋の形も変わります。** これは受け入れた判断です。
nonisolated struct StickyNote: Identifiable, Equatable, Hashable {
    let id: UUID
    /// 元になった雛形。
    let templateID: Memo.ID
    /// 一覧で見分けるための題名。**付箋は同じ雛形から何枚でも出せる**ので、
    /// 雛形の題名だけでは区別できません。
    var title: String
    /// デスクトップ上の左下位置（画面座標）。
    ///
    /// **`nil` を取りません。** 付箋は「出ている」ことが存在の条件で、
    /// はがすとはこのレコードを消すことです。位置だけ残った状態を作りません。
    var origin: CGPoint
    /// 本文の差し替え。**テキスト要素の id → 本文。**
    ///
    /// **位置ではなく id で紐づけます。** 雛形でテキスト要素を動かしても、
    /// 大きさを変えても本文は付いてきます。無い要素は雛形の本文をそのまま出します。
    var texts: [CanvasElement.ID: String]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        templateID: Memo.ID,
        title: String,
        origin: CGPoint,
        texts: [CanvasElement.ID: String] = [:],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.templateID = templateID
        self.title = title
        self.origin = origin
        self.texts = texts
        self.updatedAt = updatedAt
    }
}
