import CoreGraphics
import Foundation

/// 要素が参照する切り抜きマスク。
///
/// **実体ではなく ID を持ちます。** `CanvasElement` は値型で編集のたびに複製されるため、
/// 画素の配列を抱えると 1px 動かすたびに数 MB の複製が走ります。元画像と同じ扱いです。
///
/// マスクは PNG として、**元画像と同じアセットの保管庫**に置きます
/// （[ImageAssetRepositoryProtocol](../Repositories/ImageAssetRepositoryProtocol.swift)）。
/// 保存レイアウトも孤児の掃除も、そのまま使い回せます。
nonisolated struct CutoutMaskReference: Equatable, Hashable, Codable {
    let assetID: UUID

    /// マスクが覆う範囲。要素の枠を単位空間とした正規化座標です。
    ///
    /// **画素は PNG が持ちますが、どこを覆うかは持てません。** 被覆のある範囲まで
    /// 切り詰めて保存するため、位置と大きさをここで覚えます。
    let extent: CGRect

    /// `extent` が範囲として成立しなければ `nil`。
    /// **非有限値や 0 以下の幅を持つ参照を作らせません。**
    init?(assetID: UUID, extent: CGRect) {
        guard extent.isValidUnitExtent else {
            return nil
        }

        self.assetID = assetID
        self.extent = extent
    }
}
