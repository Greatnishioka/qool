import CoreGraphics

/// なぞりをマスクへ描く。
///
/// **多角形を作らずに直接塗ります。** 移植元は太さのある線を多角形へ変換してから
/// ブーリアン演算にかけていましたが（[BrushStrokeOutline](BrushStrokeOutline.swift)）、
/// マスクなら線をそのまま塗れます。**縁に柔らかさを持たせられるのはこちらだけ**です。
nonisolated struct CutoutMaskStamp {
    private let filters = CutoutMaskFilters()

    init() {}

    /// - Parameters:
    ///   - points: なぞった点列。要素の枠を単位空間とした座標。
    ///   - radius: 線の太さの半分。単位空間での長さ。
    ///   - softness: 縁の柔らかさ（`0...1`）。半径に対する割合です。
    ///   - width: 描くマスクの横の画素数。
    ///   - height: 縦の画素数。
    /// - Returns: 単位矩形の全体を覆うマスク。塗るものが無ければ `nil`。
    func stamp(
        points: [CGPoint],
        radius: CGFloat,
        softness: CGFloat,
        width: Int,
        height: Int,
        isClosed: Bool = false
    ) -> CutoutMask? {
        guard !points.isEmpty, width > 0, height > 0 else {
            return nil
        }

        let (pixelCount, overflowed) = width.multipliedReportingOverflow(by: height)
        guard !overflowed else {
            return nil
        }

        var coverage = [UInt8](repeating: 0, count: pixelCount)

        let drawn: Bool = coverage.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else {
                return false
            }

            // **上下を反転させます。** なぞりは左上原点、`CGContext` は左下原点です。
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.setShouldAntialias(true)
            context.setStrokeColor(gray: 1, alpha: 1)
            context.setFillColor(gray: 1, alpha: 1)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            let scaled = points.map { point in
                CGPoint(x: point.x * CGFloat(width), y: point.y * CGFloat(height))
            }

            if isClosed, scaled.count >= 3 {
                // 投げ縄は囲んだ内側を塗ります。
                context.addLines(between: scaled)
                context.closePath()
                context.fillPath()

                return true
            }

            // 太さは横方向の画素数で決めます。**縦横で画素の細かさが違っても
            // 線の太さが変わらないよう、片方に揃えます。**
            context.setLineWidth(max(1, radius * 2 * CGFloat(width)))

            if scaled.count == 1 {
                let point = scaled[0]
                let size = max(1, radius * CGFloat(width))
                context.fillEllipse(
                    in: CGRect(x: point.x - size, y: point.y - size, width: size * 2, height: size * 2)
                )
            } else {
                context.addLines(between: scaled)
                context.strokePath()
            }

            return true
        }

        guard drawn, let stamp = CutoutMask(width: width, height: height, coverage: coverage) else {
            return nil
        }

        return blurred(stamp, radius: radius, softness: softness, width: width, height: height)
    }

    /// 柔らかさのぶんだけ縁をぼかす。
    private func blurred(
        _ stamp: CutoutMask,
        radius: CGFloat,
        softness: CGFloat,
        width: Int,
        height: Int
    ) -> CutoutMask {
        let amount = min(1, max(0, softness))

        guard amount > 0 else {
            return stamp
        }

        let radiusX = Int((radius * amount * CGFloat(width)).rounded())
        let radiusY = Int((radius * amount * CGFloat(height)).rounded())

        return filters.blurred(stamp, radiusX: radiusX, radiusY: radiusY) ?? stamp
    }
}
