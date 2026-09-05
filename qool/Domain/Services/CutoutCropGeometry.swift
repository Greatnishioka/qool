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
    /// 輪郭の外に残す余白の下限（画素）。**あとから輪郭を広げ直せる幅**です。
    /// StarWindow の `displayRangeEditingPreviewMarginPixels` に合わせています。
    static let minimumMarginPixels: CGFloat = 48

    /// 切り詰めても元の面積のこの割合より小さくならないなら、書き直しません。
    /// **画像を作り直すと ID が変わり、古いファイルの掃除まで走ります。**
    /// わずかな削減のために毎回それをやる価値はありません。
    static let worthwhileAreaRatio: CGFloat = 0.9

    /// `ImageAdjustment` が輪郭の外へ広げられる最大量（表示ポイント）。
    ///
    /// **ここを余白の計算に入れないと単位が食い違います。**
    /// 余白は画素、調整はポイントで、大きな写真を小さく表示しているほど差が開きます。
    /// 足りないと、余白やぼかしを上げても画像が尽きて広がりません。
    static var adjustableMarginPoints: CGFloat {
        CGFloat(ImageAdjustment.paddingRange.upperBound + ImageAdjustment.blurRange.upperBound)
    }

    private let geometry = ContourGeometry()

    init() {}

    /// 切り詰める範囲。詰める意味がなければ `nil`。
    ///
    /// - Parameter displaySize: キャンバス上で画像を描いている大きさ。
    ///   画素と表示ポイントの比を出すために要ります。
    func crop(
        for contours: [CanvasPathContour],
        imagePixelSize: CGSize,
        displaySize: CGSize
    ) -> CutoutCrop? {
        let points = contours.flatMap { contour in
            contour.points.map { CGPoint(x: $0.x, y: $0.y) }
        }

        guard points.count >= 3,
              imagePixelSize.width > 0, imagePixelSize.height > 0,
              displaySize.width > 0, displaySize.height > 0 else {
            return nil
        }

        let margin = marginPixels(imagePixelSize: imagePixelSize, displaySize: displaySize)
        let requested = geometry.bounds(for: points)
            .insetBy(dx: -margin / imagePixelSize.width, dy: -margin / imagePixelSize.height)
            .clampedToUnit()

        let pixelRect = CGRect(
            x: requested.minX * imagePixelSize.width,
            y: requested.minY * imagePixelSize.height,
            width: requested.width * imagePixelSize.width,
            height: requested.height * imagePixelSize.height
        )
        .integral
        .intersection(CGRect(origin: .zero, size: imagePixelSize))

        guard pixelRect.width >= 1, pixelRect.height >= 1 else {
            return nil
        }

        let normalizedRect = CGRect(
            x: pixelRect.minX / imagePixelSize.width,
            y: pixelRect.minY / imagePixelSize.height,
            width: pixelRect.width / imagePixelSize.width,
            height: pixelRect.height / imagePixelSize.height
        )

        guard normalizedRect.width * normalizedRect.height < Self.worthwhileAreaRatio else {
            return nil
        }

        return CutoutCrop(pixelRect: pixelRect, normalizedRect: normalizedRect)
    }

    /// 切り詰めた画像に合わせて要素を作り直す。
    ///
    /// **画面上の見た目は変わりません。** 画像が小さくなるぶん枠も縮め、
    /// 輪郭は新しい範囲を基準に取り直します。
    func applied(_ crop: CutoutCrop, to element: CanvasElement, assetID: UUID) -> CanvasElement {
        let cropRect = crop.normalizedRect
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

    /// 調整で広げられる分を画素へ直し、下限と比べて大きいほうを採ります。
    private func marginPixels(imagePixelSize: CGSize, displaySize: CGSize) -> CGFloat {
        let scale = max(
            imagePixelSize.width / displaySize.width,
            imagePixelSize.height / displaySize.height
        )

        return max(Self.minimumMarginPixels, Self.adjustableMarginPoints * scale)
    }
}
