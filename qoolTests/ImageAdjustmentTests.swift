import Testing
@testable import qool

/// [ImageAdjustment](../qool/Domain/Models/ImageAdjustment.swift) の検証。
struct ImageAdjustmentTests {
    /// 取り込んだ画像がいきなり薄くならないための既定値。
    /// StarWindow は画像を紙の背景として敷いていたため薄い値が既定でしたが、qool では要素です。
    @Test func 初期値は見た目を変えない() {
        #expect(ImageAdjustment.default.opacity == 1)
        #expect(ImageAdjustment.default.brightness == 0)
        #expect(ImageAdjustment.default.padding == 0)
        #expect(ImageAdjustment.default.blur == 0)
    }

    /// 手で書き換えた JSON から、描画できない値が入るのを防ぎます。
    @Test func 範囲外は丸める() {
        let adjustment = ImageAdjustment(opacity: 5, brightness: -10, padding: 999, blur: .nan)

        #expect(adjustment.opacity == ImageAdjustment.opacityRange.upperBound)
        #expect(adjustment.brightness == ImageAdjustment.brightnessRange.lowerBound)
        #expect(adjustment.padding == ImageAdjustment.paddingRange.upperBound)
        #expect(adjustment.blur == ImageAdjustment.blurRange.lowerBound)
    }

    @Test func 一部だけ差し替えられる() {
        let adjustment = ImageAdjustment.default.updated(opacity: 0.5)

        #expect(adjustment.opacity == 0.5)
        #expect(adjustment.brightness == ImageAdjustment.default.brightness)
        // 差し替えでも丸めは効きます。`init` を通しているためです。
        #expect(ImageAdjustment.default.updated(padding: 999).padding == ImageAdjustment.paddingRange.upperBound)
    }
}
