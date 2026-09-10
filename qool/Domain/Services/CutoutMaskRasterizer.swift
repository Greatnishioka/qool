import CoreGraphics

/// 輪郭からマスクを起こす。
///
/// **ベクターは入力手段として残ります。** なぞり・投げ縄・矩形補正はこれからも
/// 多角形を作り、ここでマスクへ焼きます。Photoshop や Krita がパスと
/// ピクセル選択の両方を持ち、確定時にラスタライズするのと同じ関係です。
///
/// 既に多角形で保存されているメモを読み込むときの変換にも使います。
nonisolated struct CutoutMaskRasterizer {
    init() {}

    /// - Parameters:
    ///   - contours: 要素の枠を単位空間とした輪郭。**穴は偶奇規則で抜けます。**
    ///   - width: 起こすマスクの横の画素数。
    ///   - height: 縦の画素数。
    /// - Returns: 全面を覆う範囲のマスク。描けなければ `nil`。
    func mask(from contours: [CanvasPathContour], width: Int, height: Int) -> CutoutMask? {
        let (pixelCount, overflowed) = width.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, !overflowed else {
            return nil
        }

        // **開いた輪郭は塗りません。** 強引に閉じると、なぞり途中の線が面になります。
        let usable = contours.filter { $0.isClosed && $0.points.count >= 3 }
        guard !usable.isEmpty else {
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

            // **座標系を上下反転させます。** 輪郭は左上原点ですが、
            // `CGContext` は左下原点です。揃えないとマスクが裏返ります。
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)

            // 縁に中間値を持たせるのがこの形式の要点なので、必ず有効にします。
            context.setShouldAntialias(true)
            context.setFillColor(gray: 1, alpha: 1)
            context.addPath(path(for: usable, width: width, height: height))
            context.fillPath(using: .evenOdd)

            return true
        }

        guard drawn else {
            return nil
        }

        return CutoutMask(width: width, height: height, coverage: coverage)
    }

    private func path(for contours: [CanvasPathContour], width: Int, height: Int) -> CGPath {
        let path = CGMutablePath()

        for contour in contours {
            let points = contour.points.map { point in
                CGPoint(x: CGFloat(point.x) * CGFloat(width), y: CGFloat(point.y) * CGFloat(height))
            }

            guard points.count >= 3 else {
                continue
            }

            // **`addLines(between:)` は先頭の点へ自分で move します。**
            // 手前で `move(to:)` してから残りを渡すと、最初の 1 点が落ちます。
            path.addLines(between: points)
            path.closeSubpath()
        }

        return path
    }
}
