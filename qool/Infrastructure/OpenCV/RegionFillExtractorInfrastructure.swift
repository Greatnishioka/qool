import CoreGraphics
import Foundation
import opencv2

/// 押した場所から色の近い範囲を広げる（`floodFill`）。
///
/// **境界は色の変わり目が決めます。** ブラシと違って、囲まれた領域を
/// 形どおりに一度で選べます。取っ手の内側のような穴を作るための道具です。
nonisolated struct RegionFillExtractorInfrastructure: RegionMaskExtractorProtocol {
    /// 長辺をこの画素数まで縮めてから広げます。
    /// **原寸のままだと写真 1 枚で数百万画素を走査します。**
    private static let workingLongSide: Int32 = 1024

    init() {}

    func regionMask(in image: CGImage, at point: CGPoint, tolerance: Int) async -> CutoutMask? {
        await Task.detached(priority: .userInitiated) {
            Self.fill(in: image, at: point, tolerance: tolerance)
        }.value
    }

    /// **メインアクターの外で走ります。** `Mat` への変換も `floodFill` も
    /// 画素をなめるので、クリックの処理から同期で呼ぶと固まります。
    private static func fill(in image: CGImage, at point: CGPoint, tolerance: Int) -> CutoutMask? {
        let source = Mat(cgImage: image)

        guard source.rows() > 0, source.cols() > 0,
              (0..<1).contains(point.x), (0..<1).contains(point.y) else {
            return nil
        }

        let working = Self.resized(source)
        let rgb = Mat()
        Imgproc.cvtColor(src: working, dst: rgb, code: .COLOR_RGBA2RGB)

        let width = rgb.cols()
        let height = rgb.rows()
        // `floodFill` のマスクは上下左右に 1 画素ずつ広いものを要求します。
        let fillMask = Mat(
            rows: height + 2,
            cols: width + 2,
            type: CvType.CV_8UC1,
            scalar: Scalar(0)
        )

        let seed = Point2i(
            x: min(width - 1, max(0, Int32(point.x * CGFloat(width)))),
            y: min(height - 1, max(0, Int32(point.y * CGFloat(height))))
        )
        let difference = Scalar(Double(tolerance), Double(tolerance), Double(tolerance))

        // **元画像は塗りません。** `FLOODFILL_MASK_ONLY` で、広がった範囲だけを受け取ります。
        let flags = Int32(8)
            | Int32(FloodFillFlags.FLOODFILL_MASK_ONLY.rawValue)
            | (255 << 8)

        Imgproc.floodFill(
            image: rgb,
            mask: fillMask,
            seedPoint: seed,
            newVal: Scalar(0),
            rect: Rect2i(),
            loDiff: difference,
            upDiff: difference,
            flags: flags
        )

        return Self.cutoutMask(from: fillMask, width: Int(width), height: Int(height))
    }

    private static func resized(_ source: Mat) -> Mat {
        let longSide = max(source.cols(), source.rows())

        guard longSide > Self.workingLongSide else {
            return source
        }

        let scale = Double(Self.workingLongSide) / Double(longSide)
        let resized = Mat()
        Imgproc.resize(
            src: source,
            dst: resized,
            dsize: Size2i(
                width: Int32((Double(source.cols()) * scale).rounded()),
                height: Int32((Double(source.rows()) * scale).rounded())
            ),
            fx: 0,
            fy: 0,
            interpolation: InterpolationFlags.INTER_AREA.rawValue
        )

        return resized
    }

    /// 外周 1 画素の縁を落として被覆率にする。
    private static func cutoutMask(from fillMask: Mat, width: Int, height: Int) -> CutoutMask? {
        guard width > 0, height > 0 else {
            return nil
        }

        var coverage = [UInt8](repeating: 0, count: width * height)
        var filled = 0

        for row in 0..<height {
            var values = [UInt8](repeating: 0, count: width + 2)

            guard (try? fillMask.get(row: Int32(row + 1), col: 0, data: &values)) != nil else {
                continue
            }

            for column in 0..<width where values[column + 1] > 0 {
                coverage[row * width + column] = 255
                filled += 1
            }
        }

        guard filled > 0 else {
            return nil
        }

        return CutoutMask(width: width, height: height, coverage: coverage)
    }
}
