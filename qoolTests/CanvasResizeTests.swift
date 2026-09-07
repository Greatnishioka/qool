import CoreGraphics
import Foundation
import Testing
@testable import qool

/// 角を掴んでの拡大縮小の検証。
struct CanvasResizeTests {
    private let resize = ResizeCanvasElementUseCase()

    private func element(
        _ frame: CGRect = CGRect(x: 100, y: 100, width: 200, height: 100),
        rotation: Double = 0
    ) -> CanvasElement {
        CanvasElement(
            kind: .rectangle,
            frame: frame,
            fillColor: .paper,
            rotationAngleDegrees: rotation
        )
    }

    /// 回転を掛けたあとの角の位置。**掴んだ角の対角がここから動かないことが要件です。**
    private func screenCorner(_ corner: CanvasResizeCorner, of element: CanvasElement) -> CGPoint {
        let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
        let radians = element.rotationAngleDegrees * .pi / 180
        let point = corner.point(in: element.frame)
        let dx = point.x - center.x
        let dy = point.y - center.y

        return CGPoint(
            x: center.x + dx * cos(radians) - dy * sin(radians),
            y: center.y + dx * sin(radians) + dy * cos(radians)
        )
    }

    // MARK: - 変形

    @Test func 掴んだ角が指の位置へ来る() {
        let target = CGPoint(x: 400, y: 260)

        let frame = resize(element(), corner: .bottomTrailing, to: target)

        #expect(abs(frame.maxX - target.x) < 0.0001)
        #expect(abs(frame.maxY - target.y) < 0.0001)
    }

    @Test func 対角は動かない() {
        let original = element()

        let frame = resize(original, corner: .bottomTrailing, to: CGPoint(x: 400, y: 260))

        #expect(abs(frame.minX - original.frame.minX) < 0.0001)
        #expect(abs(frame.minY - original.frame.minY) < 0.0001)
    }

    /// **縦横比は保ちません。** 縦だけ引けば縦だけ伸びます。
    @Test func 縦と横は独立して変わる() {
        let original = element()

        let frame = resize(original, corner: .bottomTrailing, to: CGPoint(x: 300, y: 400))

        #expect(abs(frame.width - original.frame.width) < 0.0001)
        #expect(abs(frame.height - 300) < 0.0001)
    }

    @Test func 左上を掴めば右下が固定される() {
        let original = element()

        let frame = resize(original, corner: .topLeading, to: CGPoint(x: 50, y: 60))

        #expect(abs(frame.maxX - original.frame.maxX) < 0.0001)
        #expect(abs(frame.maxY - original.frame.maxY) < 0.0001)
        #expect(abs(frame.minX - 50) < 0.0001)
    }

    @Test func 最小の大きさより小さくならない() {
        let frame = resize(element(), corner: .bottomTrailing, to: CGPoint(x: 100, y: 100))

        #expect(frame.width >= ResizeCanvasElementUseCase.minimumSize)
        #expect(frame.height >= ResizeCanvasElementUseCase.minimumSize)
    }

    /// 対角を通り越して引いても、潰れずに反対側へ広がります。
    @Test func 対角を越えて引いても潰れない() {
        let original = element()

        let frame = resize(original, corner: .bottomTrailing, to: CGPoint(x: 0, y: 0))

        #expect(frame.width > ResizeCanvasElementUseCase.minimumSize)
        #expect(frame.maxX <= original.frame.minX + 0.0001)
    }

    // MARK: - 回転している要素

    /// **回転したまま変形します。** 固定するのは回転後の対角の位置です。
    @Test func 回転していても対角の位置は動かない() {
        let original = element(rotation: 30)
        let anchor = screenCorner(.topLeading, of: original)

        let resized = resize(original, corner: .bottomTrailing, to: CGPoint(x: 420, y: 300))
        var updated = original
        updated.frame = resized

        let movedAnchor = screenCorner(.topLeading, of: updated)

        #expect(abs(movedAnchor.x - anchor.x) < 0.0001)
        #expect(abs(movedAnchor.y - anchor.y) < 0.0001)
    }

    /// 要素自身の軸に沿って伸びます。画面の縦横ではありません。
    @Test func 回転した要素は自分の軸に沿って伸びる() {
        let original = element(rotation: 90)
        // 90 度回っているので、画面の下方向へ引くと要素の横が伸びます。
        let anchor = screenCorner(.topLeading, of: original)
        let target = CGPoint(x: anchor.x, y: anchor.y + 300)

        let frame = resize(original, corner: .bottomTrailing, to: target)

        #expect(abs(frame.width - 300) < 0.0001)
        #expect(frame.height <= ResizeCanvasElementUseCase.minimumSize + 0.0001)
    }

    // MARK: - 角を掴めるか

    @Test func 角の近くを掴める() {
        let original = element()

        #expect(resize.corner(at: CGPoint(x: 302, y: 202), of: original) == .bottomTrailing)
        #expect(resize.corner(at: CGPoint(x: 98, y: 98), of: original) == .topLeading)
    }

    @Test func 角から離れていれば掴まない() {
        #expect(resize.corner(at: CGPoint(x: 200, y: 150), of: element()) == nil)
    }

    /// **回転を戻してから比べます。** 画面上の四隅と比べると斜めの要素を掴めません。
    @Test func 回転した要素でも角を掴める() {
        let original = element(rotation: 40)
        let corner = screenCorner(.bottomTrailing, of: original)

        #expect(resize.corner(at: corner, of: original) == .bottomTrailing)
        // 回転前の位置は、もう角ではありません。
        #expect(resize.corner(at: CGPoint(x: 300, y: 200), of: original) == nil)
    }
}
