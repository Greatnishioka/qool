import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 雛形から出した付箋の検証。
///
/// **付箋は形を持たず、本文だけを持ちます。** 形は雛形のものを毎回組み立てます。
struct StickyNoteTests {
    private let composer = StickyNoteCanvasComposer()

    private func textElement(_ text: String = "雛形の本文") -> CanvasElement {
        CanvasElement(
            kind: .text,
            frame: CGRect(x: 0, y: 0, width: 100, height: 40),
            fillColor: .clear,
            text: text
        )
    }

    private func note(
        templateID: UUID = UUID(),
        texts: [CanvasElement.ID: String] = [:]
    ) -> StickyNote {
        StickyNote(
            templateID: templateID,
            title: "付箋",
            origin: CGPoint(x: 10, y: 20),
            texts: texts
        )
    }

    private func text(of canvas: Canvas, at index: Int) -> String {
        canvas.elements[index].text
    }

    // MARK: - 本文の差し込み

    @Test func 差し替えがなければ雛形の本文が出る() {
        let template = Canvas(elements: [textElement()])
        let composed = composer.canvas(for: note(), from: template)

        #expect(text(of: composed, at: 0) == "雛形の本文")
    }

    @Test func 差し替えた本文が出る() {
        let element = textElement()
        let template = Canvas(elements: [element])
        let composed = composer.canvas(
            for: note(texts: [element.id: "この付箋だけの本文"]),
            from: template
        )

        #expect(text(of: composed, at: 0) == "この付箋だけの本文")
    }

    /// **雛形は書き換えません。** 同じ雛形から何枚も組み立てるので、
    /// 1 枚目の本文が 2 枚目に漏れると使いものになりません。
    @Test func 組み立てても雛形は変わらない() {
        let element = textElement()
        let template = Canvas(elements: [element])

        _ = composer.canvas(for: note(texts: [element.id: "1 枚目"]), from: template)
        let second = composer.canvas(for: note(), from: template)

        #expect(text(of: second, at: 0) == "雛形の本文")
    }

    /// **テキスト以外へは流し込みません。** 雛形で種類が変わったときに、
    /// 関係のない要素へ本文が入るのを防ぎます。
    @Test func テキスト以外の要素は差し替えない() {
        let element = CanvasElement(
            kind: .rectangle,
            frame: CGRect(x: 0, y: 0, width: 10, height: 10),
            fillColor: .clear,
            text: "もとのまま"
        )
        let composed = composer.canvas(
            for: note(texts: [element.id: "差し替え"]),
            from: Canvas(elements: [element])
        )

        #expect(text(of: composed, at: 0) == "もとのまま")
    }

    // MARK: - 雛形を直したとき

    /// **動かしても本文は残ります。** 位置ではなく id で紐づけているためです。
    @Test func 要素を動かしても本文は残る() {
        var element = textElement()
        let sticky = note(texts: [element.id: "残ってほしい"])

        element.frame = CGRect(x: 500, y: 800, width: 300, height: 90)
        let composed = composer.canvas(for: sticky, from: Canvas(elements: [element]))

        #expect(text(of: composed, at: 0) == "残ってほしい")
    }

    @Test func 雛形から消えた要素の差し替えは捨てる() {
        let removed = textElement()
        let kept = textElement()
        let sticky = note(texts: [removed.id: "消える", kept.id: "残る"])

        let pruned = composer.pruned(sticky, against: Canvas(elements: [kept]))

        #expect(pruned.texts[removed.id] == nil)
        #expect(pruned.texts[kept.id] == "残る")
    }

    @Test func 捨てるものがなければそのまま返す() {
        let element = textElement()
        let sticky = note(texts: [element.id: "残る"])
        let pruned = composer.pruned(sticky, against: Canvas(elements: [element]))

        #expect(pruned == sticky)
    }

    /// **テキストでなくなった要素の差し替えも捨てます。**
    @Test func 種類が変わった要素の差し替えも捨てる() {
        let element = textElement()
        let changed = CanvasElement(
            id: element.id,
            kind: .rectangle,
            frame: element.frame,
            fillColor: .clear
        )
        let pruned = composer.pruned(
            note(texts: [element.id: "消える"]),
            against: Canvas(elements: [changed])
        )

        #expect(pruned.texts.isEmpty)
    }

    // MARK: - 保存の形

    @Test func 符号化して復号しても同じ() throws {
        let element = textElement()
        let original = note(texts: [element.id: "ほんぶん"])

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(StickyNote.self, from: data)

        #expect(restored == original)
    }

    /// **本文の辞書は素直な JSON になります。**
    /// 合成 `Codable` だと鍵と値が交互に並んだ配列になり、人が読めません。
    @Test func 本文は読める形で書き出される() throws {
        let element = textElement()
        let data = try JSONEncoder().encode(note(texts: [element.id: "ほんぶん"]))
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let texts = json["texts"] as? [String: String]

        #expect(texts?[element.id.uuidString] == "ほんぶん")
    }

    @Test func 読めない鍵は復号で捨てる() throws {
        let raw = """
        {"id":"\(UUID().uuidString)","templateID":"\(UUID().uuidString)","title":"付箋",
         "x":0,"y":0,"texts":{"こわれた鍵":"ほんぶん"},"updatedAt":0}
        """
        let restored = try JSONDecoder().decode(StickyNote.self, from: Data(raw.utf8))

        #expect(restored.texts.isEmpty)
    }
}
