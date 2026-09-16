import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 書式の道具を置く場所の検証。
///
/// **画面座標（左下原点）です。** 上に出すとは `y` が大きいほうへ出すことです。
struct RichTextToolbarPlacementTests {
    private let placement = RichTextToolbarPlacement()
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let panel = CGSize(width: 200, height: 40)

    private func origin(_ selection: CGRect) -> CGPoint {
        placement.origin(for: selection, panelSize: panel, within: screen)
    }

    @Test func 選択の上に出る() {
        let selection = CGRect(x: 400, y: 300, width: 100, height: 20)
        let result = origin(selection)

        #expect(result.y > selection.maxY)
    }

    @Test func 選択の中央に揃う() {
        let selection = CGRect(x: 400, y: 300, width: 100, height: 20)
        let center = origin(selection).x + panel.width / 2

        #expect(abs(center - selection.midX) < 0.001)
    }

    /// **上端に収まらないときだけ下へ回します。** 切れた道具は押せません。
    @Test func 画面の上端に収まらなければ下に出る() {
        let selection = CGRect(x: 400, y: 770, width: 100, height: 20)
        let result = origin(selection)

        #expect(result.y < selection.minY)
    }

    @Test func 左端からはみ出さない() {
        let result = origin(CGRect(x: 0, y: 300, width: 20, height: 20))

        #expect(result.x >= screen.minX)
    }

    @Test func 右端からはみ出さない() {
        let result = origin(CGRect(x: 980, y: 300, width: 20, height: 20))
        let right = result.x + panel.width

        #expect(right <= screen.maxX)
    }

    @Test func 下端からもはみ出さない() {
        let result = origin(CGRect(x: 400, y: 0, width: 100, height: 5))

        #expect(result.y >= screen.minY)
    }

    /// **原点が 0 でない画面でも、その画面の中に収めます。**
    /// 主ディスプレイの左や下に置いた副ディスプレイは、原点が負になります。
    @Test func 原点が負の画面でもその画面に収まる() {
        let secondary = CGRect(x: -1600, y: -400, width: 1200, height: 700)
        let result = placement.origin(
            for: CGRect(x: -1590, y: -300, width: 20, height: 20),
            panelSize: panel,
            within: secondary
        )

        #expect(result.x >= secondary.minX)
        #expect(result.x + panel.width <= secondary.maxX)
        #expect(result.y >= secondary.minY)
        #expect(result.y + panel.height <= secondary.maxY)
    }

    /// **画面より大きい道具でも落ちません。** `min(max(…))` の順序が壊れる形です。
    @Test func 画面より大きくても値が返る() {
        let result = placement.origin(
            for: CGRect(x: 400, y: 300, width: 100, height: 20),
            panelSize: CGSize(width: 2000, height: 2000),
            within: screen
        )

        #expect(result.x >= screen.minX)
        #expect(result.y >= screen.minY)
    }
}
