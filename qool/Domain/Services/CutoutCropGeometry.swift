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
    /// - Parameter covering: 必ず含める範囲。**薄く覆っている部分を切り落とさないため**に渡します。
    ///   輪郭はしきい値を超えた濃さの部分しか表さないので、髪やガラスのような
    ///   薄い被覆が輪郭の外にあると、これが無いと画像側が捨てられます。
    func crop(
        for contours: [CanvasPathContour],
        imagePixelSize: CGSize,
        displaySize: CGSize,
        covering additionalBounds: CGRect? = nil
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
        let covered = additionalBounds.map { geometry.bounds(for: points).union($0) }
            ?? geometry.bounds(for: points)
        let requested = covered
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
    ///
    /// 切り詰め前のアセットは `imageSource` に残します。**捨てると解除で戻せません。**
    func applied(_ crop: CutoutCrop, to element: CanvasElement, assetID: UUID) -> CanvasElement {
        let cropRect = crop.normalizedRect
        var updated = element
        updated.imageSource = source(of: element, croppedBy: cropRect)
        updated.imageAssetID = assetID
        // **マスクは持ち越しません。** 画素の意味する範囲が変わるので、
        // 切り詰めたあとに焼き直します。
        updated.cutoutMask = nil
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

    /// 切り詰めた枠を基準に、マスクの覆う範囲を取り直す。
    ///
    /// **輪郭と同じ変換をマスクにも掛ける必要があります。** 掛けないと、
    /// 切り詰め前の座標のまま新しい枠で解釈され、絵が縮んで見えます。
    /// 画素はそのままで、覆う範囲だけが変わります。
    func applied(_ crop: CutoutCrop, to mask: CutoutMask) -> CutoutMask? {
        let cropRect = crop.normalizedRect

        guard cropRect.width > 0, cropRect.height > 0 else {
            return nil
        }

        return CutoutMask(
            extent: CGRect(
                x: (mask.extent.minX - cropRect.minX) / cropRect.width,
                y: (mask.extent.minY - cropRect.minY) / cropRect.height,
                width: mask.extent.width / cropRect.width,
                height: mask.extent.height / cropRect.height
            ),
            width: mask.width,
            height: mask.height,
            coverage: mask.coverage
        )
    }

    /// 切り詰めを取り消し、元画像を表示する要素へ戻す。`applied` の逆です。
    ///
    /// **枠は今の位置を基準に広げます。** 切り詰めたあとに動かしていても、
    /// 見えている絵がその場に残るようにするためです。
    /// 切り詰めていない要素（`imageSource` が `nil`）はそのまま返します。
    func restored(_ element: CanvasElement) -> CanvasElement {
        guard let source = element.imageSource,
              source.cropRect.width > 0, source.cropRect.height > 0 else {
            return element
        }

        let cropRect = source.cropRect
        let width = element.frame.width / cropRect.width
        let height = element.frame.height / cropRect.height

        var updated = element
        updated.imageAssetID = source.assetID
        updated.imageSource = nil
        updated.cutoutMask = nil
        updated.frame = CGRect(
            x: element.frame.minX - cropRect.minX * width,
            y: element.frame.minY - cropRect.minY * height,
            width: width,
            height: height
        )
        updated.pathContours = element.pathContours.map { contour in
            CanvasPathContour(
                points: contour.points.map { point in
                    NormalizedPoint(
                        x: cropRect.minX + point.x * cropRect.width,
                        y: cropRect.minY + point.y * cropRect.height
                    )
                },
                isClosed: contour.isClosed
            )
        }

        return updated
    }

    /// 切り詰め前の画像への参照を更新する。
    ///
    /// **2 回目以降の切り抜きでも、指す先は最初の画像のままです。**
    /// 途中の切り詰め画像は戻る先にならないので、範囲だけを掛け合わせて引き継ぎます。
    private func source(of element: CanvasElement, croppedBy cropRect: CGRect) -> CutoutImageSource? {
        guard let existing = element.imageSource else {
            return element.imageAssetID.map { assetID in
                CutoutImageSource(assetID: assetID, cropRect: cropRect)
            }
        }

        let previous = existing.cropRect

        return CutoutImageSource(
            assetID: existing.assetID,
            cropRect: CGRect(
                x: previous.minX + cropRect.minX * previous.width,
                y: previous.minY + cropRect.minY * previous.height,
                width: previous.width * cropRect.width,
                height: previous.height * cropRect.height
            )
        )
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
