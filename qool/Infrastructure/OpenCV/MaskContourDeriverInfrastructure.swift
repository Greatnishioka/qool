import CoreGraphics
import Foundation
import opencv2

/// マスクから輪郭を取り出す。
///
/// **プレビューと採点にだけ使います。** 切り抜きの正はマスクのままで、
/// ここで作る輪郭は「どこが切り抜かれるか」を線で示すためのものです。
nonisolated struct MaskContourDeriverInfrastructure: MaskContourDeriverProtocol {
    /// 輪郭として成立する最小の点数。
    private static let minimumPointCount = 8

    init() {}

    func contours(from mask: CutoutMask, threshold: UInt8 = 128) -> [[CGPoint]] {
        guard mask.width > 0, mask.height > 0 else {
            return []
        }

        let source = Mat(rows: Int32(mask.height), cols: Int32(mask.width), type: CvType.CV_8UC1)

        guard (try? source.put(row: 0, col: 0, data: mask.coverage)) != nil else {
            return []
        }

        let binary = Mat()
        Imgproc.threshold(
            src: source,
            dst: binary,
            thresh: Double(threshold),
            maxval: 255,
            type: .THRESH_BINARY
        )

        var found: [[Point2i]] = []
        Imgproc.findContours(
            image: binary,
            contours: &found,
            hierarchy: Mat(),
            mode: .RETR_EXTERNAL,
            // 点を畳むと、四角い被写体が 4 点になって点数の下限で弾かれます。
            method: .CHAIN_APPROX_NONE
        )

        let width = CGFloat(mask.width)
        let height = CGFloat(mask.height)

        return found
            .map { points in
                points.map { point in
                    // マスクの画素を、要素の枠を単位空間とした座標へ直します。
                    CGPoint(
                        x: mask.extent.minX + CGFloat(point.x) / width * mask.extent.width,
                        y: mask.extent.minY + CGFloat(point.y) / height * mask.extent.height
                    )
                }
            }
            .filter { $0.count >= Self.minimumPointCount }
            .sorted { first, second in area(of: first) > area(of: second) }
    }

    private func area(of points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else {
            return 0
        }

        var total: CGFloat = 0

        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            total += current.x * next.y - next.x * current.y
        }

        return abs(total / 2)
    }
}
