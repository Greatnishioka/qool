import CoreGraphics
import Foundation

/// 切り抜きが決まった元画像を、どこまで切り詰めてよいかを決める。
///
/// **保存するのは切り抜き結果ではなく元画像です**
/// （[画像アセットの持ち方](../../../docs/architecture/persistence.md#画像アセットの持ち方)）。
/// 切り抜き後の絵だけを残すと、あとから輪郭を直せなくなります。
/// そのぶん原寸を抱えると写真 1 枚で数 MB になるため、
/// **輪郭の外側に余白を付けた範囲まで切り詰めて「元画像」とします。**
nonisolated struct CutoutCropGeometry {
    /// 輪郭の外に残す余白（px）。**あとから輪郭を広げ直せる幅**です。
    /// StarWindow の `displayRangeEditingPreviewMarginPixels` に合わせています。
    static let marginPixels: CGFloat = 48

    /// 切り詰めても元の面積のこの割合より小さくならないなら、書き直しません。
    /// **画像を作り直すと ID が変わり、古いファイルの掃除まで走ります。**
    /// わずかな削減のために毎回それをやる価値はありません。
    static let worthwhileAreaRatio: CGFloat = 0.9

    private let geometry = ContourGeometry()

    init() {}

    /// 切り詰める範囲（正規化）。詰める意味がなければ `nil`。
    func cropRect(for contours: [CanvasPathContour], imagePixelSize: CGSize) -> CGRect? {
        let points = contours.flatMap { contour in
            contour.points.map { CGPoint(x: $0.x, y: $0.y) }
        }

        guard points.count >= 3, imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            return nil
        }

        let cropRect = geometry.bounds(for: points)
            .insetBy(
                dx: -Self.marginPixels / imagePixelSize.width,
                dy: -Self.marginPixels / imagePixelSize.height
            )
            .clampedToUnit()

        guard cropRect.width * cropRect.height < Self.worthwhileAreaRatio else {
            return nil
        }

        return cropRect
    }

    /// 切り詰めた画像に合わせて要素を作り直す。
    ///
    /// **画面上の見た目は変わりません。** 画像が小さくなるぶん枠も縮め、
    /// 輪郭は新しい範囲を基準に取り直します。
    func applied(_ cropRect: CGRect, to element: CanvasElement, assetID: UUID) -> CanvasElement {
        var updated = element
        updated.imageAssetID = assetID
        updated.frame = CGRect(
            x: element.frame.minX + cropRect.minX * element.frame.width,
            y: element.frame.minY + cropRect.minY * element.frame.height,
            width: cropRect.width * element.frame.width,
            height: cropRect.height * element.frame.height
        )
        updated.pathContours = element.pathContours.map { contour in
            CanvasPathContour(
                points: contour.points.map { point in
                    NormalizedPoint(
                        x: (point.x - cropRect.minX) / cropRect.width,
                        y: (point.y - cropRect.minY) / cropRect.height
                    )
                },
                isClosed: contour.isClosed
            )
        }

        return updated
    }

    /// 正規化した範囲を、画素の格子に載る矩形へ直す。
    func pixelRect(for cropRect: CGRect, imagePixelSize: CGSize) -> CGRect {
        CGRect(
            x: cropRect.minX * imagePixelSize.width,
            y: cropRect.minY * imagePixelSize.height,
            width: cropRect.width * imagePixelSize.width,
            height: cropRect.height * imagePixelSize.height
        )
        .integral
    }
}
