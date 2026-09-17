import Foundation

/// 出したばかりの付箋に付ける題名を決める。
///
/// **同じ雛形から何枚でも出せるので、雛形の題名だけでは見分けられません**
/// （[#29](https://github.com/Greatnishioka/qool/issues/29)）。2 枚目からは番号を足します。
nonisolated struct StickyNoteNaming {
    init() {}

    /// **空いている一番小さい番号を使います。** 枚数で決めると、間の 1 枚を
    /// はがしたあとに同じ番号が 2 つ並びます。
    func title(forTemplate template: Memo, existing: [StickyNote]) -> String {
        let used = Set(existing.filter { $0.templateID == template.id }.map(\.title))

        guard used.contains(template.title) else {
            return template.title
        }

        var number = 2

        while used.contains("\(template.title) \(number)") {
            number += 1
        }

        return "\(template.title) \(number)"
    }
}
