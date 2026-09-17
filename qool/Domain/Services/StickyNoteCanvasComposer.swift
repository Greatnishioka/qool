import Foundation

/// 雛形の形に、付箋の本文を差し込む。
///
/// **付箋は形を持ちません。** 描くときに毎回ここで組み立てます
/// （[#29](https://github.com/Greatnishioka/qool/issues/29)）。
nonisolated struct StickyNoteCanvasComposer {
    init() {}

    /// 付箋として描く canvas。
    ///
    /// **差し替えるのはテキスト要素だけです。** 雛形で要素の種類が変わった場合に、
    /// 関係のない要素へ本文を流し込まないためです。
    func canvas(for note: StickyNote, from template: Canvas) -> Canvas {
        var composed = template

        for index in composed.elements.indices {
            guard composed.elements[index].kind == .text,
                  let text = note.texts[composed.elements[index].id] else {
                continue
            }

            composed.elements[index].text = text
        }

        return composed
    }

    /// 雛形に無くなったテキスト要素の差し替えを落とす。
    ///
    /// **黙って捨てます。** 差し替え先が消えた本文は出しようがなく、
    /// 抱えたままだと保存のたびに増え続けます。
    ///
    /// **消えたときだけ落ちます。** 動かしても大きさを変えても `id` は変わらないので、
    /// 本文は残ります。
    func pruned(_ note: StickyNote, against template: Canvas) -> StickyNote {
        let textElementIDs = Set(
            template.elements.filter { $0.kind == .text }.map(\.id)
        )

        guard !note.texts.keys.allSatisfy(textElementIDs.contains) else {
            return note
        }

        var pruned = note
        pruned.texts = note.texts.filter { textElementIDs.contains($0.key) }

        return pruned
    }
}
