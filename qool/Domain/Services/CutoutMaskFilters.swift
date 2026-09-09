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

        let horizontal = maximumAlongRows(padded, width: width, height: height, radius: radiusX)
        let coverage = maximumAlongColumns(horizontal, width: width, height: height, radius: radiusY)

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

    /// **単調減少の窓で走らせます。** 半径ぶんを毎回見直すと、
    /// 余白が広いときに画素数 × 半径の計算量になります。
    private func maximumAlongRows(
        _ values: [UInt8],
        width: Int,
        height: Int,
        radius: Int
    ) -> [UInt8] {
        guard radius > 0 else {
            return values
        }

        var result = values

        for row in 0..<height {
            let offset = row * width
            let line = Array(values[offset..<(offset + width)])
            let filtered = slidingMaximum(line, radius: radius)
            result.replaceSubrange(offset..<(offset + width), with: filtered)
        }

        return result
    }

    private func maximumAlongColumns(
        _ values: [UInt8],
        width: Int,
        height: Int,
        radius: Int
    ) -> [UInt8] {
        guard radius > 0 else {
            return values
        }

        var result = values

        for column in 0..<width {
            let line = (0..<height).map { row in values[row * width + column] }
            let filtered = slidingMaximum(line, radius: radius)

            for row in 0..<height {
                result[row * width + column] = filtered[row]
            }
        }

        return result
    }

    /// 幅 `radius * 2 + 1` の窓での最大値。要素の数に比例した手数で終わります。
    private func slidingMaximum(_ values: [UInt8], radius: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: values.count)
        // 値が単調減少になるよう保つ添字の並び。先頭が窓の中の最大値です。
        var indices: [Int] = []
        var head = 0

        for index in values.indices {
            while indices.count > head, values[indices[indices.count - 1]] <= values[index] {
                indices.removeLast()
            }

            indices.append(index)

            if indices[head] < index - radius * 2 {
                head += 1
            }

            if index >= radius {
                result[index - radius] = values[indices[head]]
            }
        }

        // 右端は窓が外へはみ出すので、残りを詰めます。
        for index in max(0, values.count - radius)..<values.count {
            while indices.count > head, indices[head] < index - radius {
                head += 1
            }

            result[index] = values[indices[head]]
        }

        return result
    }
}
