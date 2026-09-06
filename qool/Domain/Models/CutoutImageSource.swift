import CoreGraphics
import Foundation

/// 切り詰める前の元画像への参照。
///
/// **切り抜きを適用すると、元画像は「輪郭 + 余白」の範囲まで切り詰められます**
/// （[CutoutCropGeometry](../Services/CutoutCropGeometry.swift)）。
/// 切り詰めた絵しか残らないと切り抜きを解除しても元へ戻せないため、
/// 切り詰め前のアセットと、そこから見た今の画像の範囲を覚えておきます。
nonisolated struct CutoutImageSource: Equatable, Hashable, Codable {
    /// 切り詰め前の画像アセット。**要素が参照している間は掃除されません**
    /// （[PruneImageAssetsUseCase](../../Application/UseCases/Image/PruneImageAssetsUseCase.swift)）。
    let assetID: UUID

    /// `assetID` の画像を単位空間としたときの、今の画像の範囲。
    ///
    /// **切り抜きを繰り返しても、常にいちばん最初の画像から見た範囲です。**
    /// 途中の切り詰め画像は戻る先にならないので、範囲だけを掛け合わせて引き継ぎます。
    let cropRect: CGRect

    init(assetID: UUID, cropRect: CGRect) {
        self.assetID = assetID
        self.cropRect = cropRect
    }
}
