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

    /// 画素数を変えたマスク。**覆う範囲は変わりません。**
    ///
    /// 抽出器は元画像の画素数でマスクを返しますが、表示に必要な細かさはそれより
    /// ずっと粗いことがあります（[#16](https://github.com/Greatnishioka/qool/issues/16)）。
    func resized(_ mask: CutoutMask, width: Int, height: Int) -> CutoutMask? {
        guard width > 0, height > 0 else {
            return nil
        }

        guard width != mask.width || height != mask.height else {
            return mask
        }

        let (pixelCount, overflowed) = width.multipliedReportingOverflow(by: height)
        guard !overflowed else {
            return nil
        }

        var coverage = [UInt8](repeating: 0, count: pixelCount)
        var source = mask.coverage

        let drawn: Bool = source.withUnsafeMutableBytes { sourceBuffer in
            guard let sourceAddress = sourceBuffer.baseAddress,
                  let sourceContext = CGContext(
                      data: sourceAddress,
                      width: mask.width,
                      height: mask.height,
                      bitsPerComponent: 8,
                      bytesPerRow: mask.width,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ),
                  let image = sourceContext.makeImage() else {
                return false
            }

            return coverage.withUnsafeMutableBytes { destination in
                guard let destinationAddress = destination.baseAddress,
                      let context = CGContext(
                          data: destinationAddress,
                          width: width,
                          height: height,
                          bitsPerComponent: 8,
                          bytesPerRow: width,
                          space: CGColorSpaceCreateDeviceGray(),
                          bitmapInfo: CGImageAlphaInfo.none.rawValue
                      ) else {
                    return false
                }

                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

                return true
            }
        }

        guard drawn else {
            return nil
        }

        return CutoutMask(extent: mask.extent, width: width, height: height, coverage: coverage)
    }

    /// ぼかしたマスク。**ブラシの柔らかさに使います。**
    ///
    /// 窓の中の平均を取ります。走査するたびに足し直さず、**出入りする 1 画素だけを
    /// 加減する**ので、半径を広げても手数は変わりません。
    func blurred(_ mask: CutoutMask, radiusX: Int, radiusY: Int) -> CutoutMask? {
        guard radiusX > 0 || radiusY > 0 else {
            return mask
        }

        var coverage = mask.coverage
        var scratch = mask.coverage
        let width = mask.width
        let height = mask.height

        if radiusX > 0 {
            coverage.withUnsafeBufferPointer { source in
                scratch.withUnsafeMutableBufferPointer { destination in
                    for row in 0..<height {
                        movingAverage(
                            source: source.baseAddress!,
                            destination: destination.baseAddress!,
                            start: row * width,
                            count: width,
                            step: 1,
                            radius: radiusX
                        )
                    }
                }
            }
            swap(&coverage, &scratch)
        }

        if radiusY > 0 {
            coverage.withUnsafeBufferPointer { source in
                scratch.withUnsafeMutableBufferPointer { destination in
                    for column in 0..<width {
                        movingAverage(
                            source: source.baseAddress!,
                            destination: destination.baseAddress!,
                            start: column,
                            count: height,
                            step: width,
                            radius: radiusY
                        )
                    }
                }
            }
            swap(&coverage, &scratch)
        }

        return CutoutMask(extent: mask.extent, width: width, height: height, coverage: coverage)
    }

    /// 単位矩形の全体を覆うマスクへ置き直す。
    ///
    /// **編集の間はこの形で持ちます。** 切り詰めた範囲のまま合成しようとすると、
    /// なぞりが今の形の外へ出るたびに範囲を広げ直すことになります。
    /// 同じ格子に載せてしまえば、合成は画素どうしの比較だけで済みます。
    func placedInUnitSpace(_ mask: CutoutMask, width: Int, height: Int) -> CutoutMask? {
        guard width > 0, height > 0 else {
            return nil
        }

        let (pixelCount, overflowed) = width.multipliedReportingOverflow(by: height)
        guard !overflowed else {
            return nil
        }

        var coverage = [UInt8](repeating: 0, count: pixelCount)
        let extent = mask.extent

        for row in 0..<height {
            // 出力の画素の中心が、元のマスクのどこに当たるか。
            let y = (CGFloat(row) + 0.5) / CGFloat(height)
            let sourceY = (y - extent.minY) / extent.height * CGFloat(mask.height)

            guard sourceY >= 0, sourceY < CGFloat(mask.height) else {
                continue
            }

            let sourceRow = Int(sourceY) * mask.width

            for column in 0..<width {
                let x = (CGFloat(column) + 0.5) / CGFloat(width)
                let sourceX = (x - extent.minX) / extent.width * CGFloat(mask.width)

                guard sourceX >= 0, sourceX < CGFloat(mask.width) else {
                    continue
                }

                coverage[row * width + column] = mask.coverage[sourceRow + Int(sourceX)]
            }
        }

        return CutoutMask(width: width, height: height, coverage: coverage)
    }

    // MARK: - 平均フィルタ

    /// 窓の中の平均。出入りする画素だけを加減します。
    private func movingAverage(
        source: UnsafePointer<UInt8>,
        destination: UnsafeMutablePointer<UInt8>,
        start: Int,
        count: Int,
        step: Int,
        radius: Int
    ) {
        var total = 0

        // 最初の窓。範囲の外は端の値が続くものとして扱います。
        for index in -radius...radius {
            total += Int(source[start + min(count - 1, max(0, index)) * step])
        }

        let window = radius * 2 + 1

        for index in 0..<count {
            destination[start + index * step] = UInt8(total / window)

            let leaving = min(count - 1, max(0, index - radius))
            let entering = min(count - 1, max(0, index + radius + 1))
            total += Int(source[start + entering * step]) - Int(source[start + leaving * step])
        }
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
