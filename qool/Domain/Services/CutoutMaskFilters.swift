import CoreGraphics

/// マスクを加工する。
///
/// **余白は輪郭の押し出しではなく、マスクの膨張で作ります。**
/// 移植元の [ContourPadding](ContourPadding.swift) は重心から放射状に押し出す近似で、
/// 凹凸のある形では角ばり、描画側の膨らませ方とも食い違っていました
/// （[issue #10](https://github.com/Greatnishioka/qool/issues/10)）。
/// 画素ごとの最大値を取る膨張なら、どの向きにも同じだけ広がります。
nonisolated struct CutoutMaskFilters {
    init() {}

    /// 縦横それぞれの半径で膨らませたマスク。
    ///
    /// **縦横を別々に受け取ります。** 要素は非等比に変形できるため、
    /// 表示上で同じ幅の余白でも、マスク上では縦横で画素数が変わります。
    ///
    /// 広がる分だけ画素も増やすので、**縁で切られません。**
    func dilated(_ mask: CutoutMask, radiusX: Int, radiusY: Int) -> CutoutMask? {
        guard radiusX > 0 || radiusY > 0 else {
            return mask
        }

        let width = mask.width + radiusX * 2
        let height = mask.height + radiusY * 2

        var padded = [UInt8](repeating: 0, count: width * height)
        for row in 0..<mask.height {
            let source = row * mask.width
            let destination = (row + radiusY) * width + radiusX
            padded.replaceSubrange(
                destination..<(destination + mask.width),
                with: mask.coverage[source..<(source + mask.width)]
            )
        }

        let coverage = maximumFiltered(
            padded,
            width: width,
            height: height,
            radiusX: radiusX,
            radiusY: radiusY
        )

        // 覆う範囲も、増やした画素のぶん広げます。
        let scaleX = mask.extent.width / CGFloat(mask.width)
        let scaleY = mask.extent.height / CGFloat(mask.height)

        return CutoutMask(
            extent: CGRect(
                x: mask.extent.minX - CGFloat(radiusX) * scaleX,
                y: mask.extent.minY - CGFloat(radiusY) * scaleY,
                width: CGFloat(width) * scaleX,
                height: CGFloat(height) * scaleY
            ),
            width: width,
            height: height,
            coverage: coverage
        )
    }

    /// 表示ポイントでの余白を、マスク上の画素数へ直す。
    ///
    /// **非等比に変形されていると縦横で比が変わります。** 片方の比だけで換算すると、
    /// 引き伸ばした向きの余白が細くなります。
    func radius(
        forPointPadding padding: CGFloat,
        mask: CutoutMask,
        elementSize: CGSize
    ) -> (x: Int, y: Int) {
        guard padding > 0,
              elementSize.width > 0, elementSize.height > 0,
              mask.extent.width > 0, mask.extent.height > 0 else {
            return (0, 0)
        }

        // マスク 1 画素が表示上で何ポイントぶんか。
        let pointsPerPixelX = elementSize.width * mask.extent.width / CGFloat(mask.width)
        let pointsPerPixelY = elementSize.height * mask.extent.height / CGFloat(mask.height)

        return (
            x: max(0, Int((padding / max(pointsPerPixelX, 0.0001)).rounded())),
            y: max(0, Int((padding / max(pointsPerPixelY, 0.0001)).rounded()))
        )
    }

    // MARK: - 最大値フィルタ

    /// **確保を使い回します。** 。
    private func maximumFiltered(
        _ values: [UInt8],
        width: Int,
        height: Int,
        radiusX: Int,
        radiusY: Int
    ) -> [UInt8] {
        var horizontal = values
        var result = values
        // 単調減少の窓に使う添字。行と列で長いほうに合わせて 1 度だけ確保します。
        var window = [Int](repeating: 0, count: max(width, height))

        values.withUnsafeBufferPointer { source in
            horizontal.withUnsafeMutableBufferPointer { destination in
                window.withUnsafeMutableBufferPointer { window in
                    guard radiusX > 0 else {
                        return
                    }

                    for row in 0..<height {
                        slidingMaximum(
                            source: source.baseAddress!,
                            destination: destination.baseAddress!,
                            start: row * width,
                            count: width,
                            step: 1,
                            radius: radiusX,
                            window: window.baseAddress!
                        )
                    }
                }
            }
        }

        horizontal.withUnsafeBufferPointer { source in
            result.withUnsafeMutableBufferPointer { destination in
                window.withUnsafeMutableBufferPointer { window in
                    guard radiusY > 0 else {
                        return
                    }

                    for column in 0..<width {
                        slidingMaximum(
                            source: source.baseAddress!,
                            destination: destination.baseAddress!,
                            start: column,
                            count: height,
                            step: width,
                            radius: radiusY,
                            window: window.baseAddress!
                        )
                    }
                }
            }
        }

        return radiusY > 0 ? result : horizontal
    }

    /// 幅 `radius * 2 + 1` の窓での最大値。**要素の数に比例した手数で終わります。**
    ///
    /// `step` は隣の要素までの間隔です。列を走るときは行の幅になるので、
    /// 行と列で同じ処理を使い回せます。
    private func slidingMaximum(
        source: UnsafePointer<UInt8>,
        destination: UnsafeMutablePointer<UInt8>,
        start: Int,
        count: Int,
        step: Int,
        radius: Int,
        window: UnsafeMutablePointer<Int>
    ) {
        var head = 0
        var tail = 0

        for index in 0..<count {
            let value = source[start + index * step]

            while tail > head, source[start + window[tail - 1] * step] <= value {
                tail -= 1
            }

            window[tail] = index
            tail += 1

            if window[head] < index - radius * 2 {
                head += 1
            }

            if index >= radius {
                destination[start + (index - radius) * step] = source[start + window[head] * step]
            }
        }

        // 右端（下端）は窓が外へはみ出すので、残りを詰めます。
        for index in max(0, count - radius)..<count {
            while tail > head, window[head] < index - radius {
                head += 1
            }

            destination[start + index * step] = source[start + window[head] * step]
        }
    }
}
