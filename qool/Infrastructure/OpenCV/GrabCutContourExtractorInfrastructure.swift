import CoreGraphics
import Foundation
import opencv2

/// なぞった範囲を種にして、色の分布から前景と背景を分ける。
///
/// **Vision の被写体マスクが効かない画像のための抽出器です。**
/// 白背景の白い商品のように、被写体検出が曖昧なマスクしか返さない画像でも、
/// 色に差があれば分離できます。
///
/// なぞり線をそのまま種として渡すのが要点です。矩形で初期化する使い方もありますが、
/// **なぞりの形を捨てるとカップの取っ手のような凹みが最初から埋まります。**
nonisolated struct GrabCutContourExtractorInfrastructure: CutoutMaskExtractorProtocol {
    /// 反復回数。増やすほど精度が上がりますが、その分遅くなります。
    private static let iterationCount: Int32 = 4

    /// 長辺をこの画素数まで縮めてから解きます。
    /// **原寸のままだと数秒かかります。** 輪郭は縮小しても十分な精度で取れます。
    private static let workingLongSide: Int32 = 512

    /// なぞりの外側にも背景と決めつけない余地を残す幅（正規化）。
    private static let guideMargin: CGFloat = 0.04

    private let geometry = ContourGeometry()

    init() {}

    func extractMask(in image: CGImage, guidedBy guide: [CGPoint]) async -> CutoutMask? {
        guard guide.count >= 3 else {
            return nil
        }

        let source = Mat(cgImage: image)
        guard source.rows() > 0, source.cols() > 0 else {
            return nil
        }

        let working = resized(source)
        let rgb = Mat()
        Imgproc.cvtColor(src: working, dst: rgb, code: .COLOR_RGBA2RGB)

        let mask = seedMask(for: guide, width: rgb.cols(), height: rgb.rows())
        let background = Mat()
        let foreground = Mat()

        Imgproc.grabCut(
            img: rgb,
            mask: mask,
            rect: Rect2i(x: 0, y: 0, width: rgb.cols(), height: rgb.rows()),
            bgdModel: background,
            fgdModel: foreground,
            iterCount: Self.iterationCount,
            mode: GrabCutModes.GC_INIT_WITH_MASK.rawValue
        )

        return cutoutMask(from: mask)
    }

    /// 長辺を `workingLongSide` に収めた画像。小さければそのまま使います。
    private func resized(_ source: Mat) -> Mat {
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

    /// 種になるマスク。
    ///
    /// - なぞりの内側 → 前景かもしれない
    /// - なぞりの少し外まで → 背景かもしれない
    /// - それより外 → 背景と決めつける
    ///
    /// **決めつける領域を作らないと `grabCut` が解けません。**
    /// 全部が「かもしれない」だと、背景の色分布を推定する材料がなくなります。
    private func seedMask(for guide: [CGPoint], width: Int32, height: Int32) -> Mat {
        let mask = Mat(
            rows: height,
            cols: width,
            type: CvType.CV_8UC1,
            scalar: Scalar(Double(GrabCutClasses.GC_BGD.rawValue))
        )

        let margin = geometry.bounds(for: guide)
            .insetBy(dx: -Self.guideMargin, dy: -Self.guideMargin)
            .clampedToUnit()

        Imgproc.rectangle(
            img: mask,
            rec: Rect2i(
                x: Int32(margin.minX * CGFloat(width)),
                y: Int32(margin.minY * CGFloat(height)),
                width: max(1, Int32(margin.width * CGFloat(width))),
                height: max(1, Int32(margin.height * CGFloat(height)))
            ),
            color: Scalar(Double(GrabCutClasses.GC_PR_BGD.rawValue)),
            thickness: -1
        )

        let polygon = guide.map { point in
            Point2i(x: Int32(point.x * CGFloat(width)), y: Int32(point.y * CGFloat(height)))
        }
        Imgproc.fillPoly(
            img: mask,
            pts: [polygon],
            color: Scalar(Double(GrabCutClasses.GC_PR_FGD.rawValue))
        )

        return mask
    }

    /// `grabCut` の結果を被覆率へ直す。
    ///
    /// **2 値です。** `grabCut` は前景か背景かしか返さないので、
    /// Vision のマスクのような縁の半透明は持ちません。
    private func cutoutMask(from mask: Mat) -> CutoutMask? {
        // 前景は「確定」と「たぶん」の 2 つ。どちらも残します。
        let foreground = Mat()
        let probableForeground = Mat()
        let certain = Double(GrabCutClasses.GC_FGD.rawValue)
        let probable = Double(GrabCutClasses.GC_PR_FGD.rawValue)
        Core.inRange(src: mask, lowerb: Scalar(certain), upperb: Scalar(certain), dst: foreground)
        Core.inRange(src: mask, lowerb: Scalar(probable), upperb: Scalar(probable), dst: probableForeground)

        let binary = Mat()
        Core.bitwise_or(src1: foreground, src2: probableForeground, dst: binary)

        let width = Int(binary.cols())
        let height = Int(binary.rows())

        guard width > 0, height > 0 else {
            return nil
        }

        var coverage = [UInt8](repeating: 0, count: width * height)

        for row in 0..<height {
            var values = [UInt8](repeating: 0, count: width)

            guard (try? binary.get(row: Int32(row), col: 0, data: &values)) != nil else {
                continue
            }

            for column in 0..<width {
                // **`Mat.get` は符号付きで返します。** そのまま丸めると 255 が -1 になり、
                // マスク全体が空になります。ビット列として読み替えます。
                coverage[row * width + column] = UInt8(min(255, max(0, values[column])))
            }
        }

        return CutoutMask(width: width, height: height, coverage: coverage)
    }
}
