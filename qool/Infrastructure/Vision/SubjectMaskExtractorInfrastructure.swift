import CoreVideo
import Foundation
import Vision

/// Vision の前景インスタンスマスクから被写体の輪郭を作る。
///
/// StarWindow からの移植ですが、**Vision の呼び出しは書き換えています。**
/// 移植元は `VNGenerateForegroundInstanceMaskRequest`（旧 API）で、
/// こちらは Swift 版の `GenerateForegroundInstanceMaskRequest` を使います。
///
/// なぞりの内側にあるインスタンスだけを選ぶので、**背景や隣の物体は拾いません。**
/// 輪郭化は放射状に 160 本のレイを飛ばし、中心から見て最も遠いマスク上の点を拾う方式です。
nonisolated struct SubjectMaskExtractorInfrastructure: SubjectContourExtractorProtocol {
    /// 輪郭として成立する最小の点数。
    private static let minimumPointCount = 8
    private static let rayCount = 160
    /// 1 本のレイを刻む段数。
    private static let raySteps = 220
    /// これを超えたらマスクの内側とみなす。
    private static let maskThreshold: Float = 0.08
    /// なぞりの外側も少し見ます。被写体がなぞりからはみ出しても拾えるようにするためです。
    private static let guideInset: CGFloat = -0.05
    /// なぞりの内側を何分割して調べるか。全画素を見る必要はありません。
    private static let guideSampleSteps = 40
    /// `instanceAtPoint` が背景に対して返す番号。
    private static let backgroundInstance = 0

    private let geometry = ContourGeometry()

    init() {}

    func extractContour(in image: CGImage, guidedBy guide: [CGPoint]) async -> [CGPoint]? {
        guard guide.count >= 3 else {
            return nil
        }

        let handler = ImageRequestHandler(image)

        do {
            guard let observation = try await handler.perform(GenerateForegroundInstanceMaskRequest()) else {
                return nil
            }

            let instances = instancesInsideGuide(of: observation, guide: guide)
            guard !instances.isEmpty else {
                return nil
            }

            let mask = try observation.generateScaledMask(for: instances, scaledToImageFrom: handler)
            let contour = contourFromMask(mask, guidedBy: guide)

            return contour.count >= Self.minimumPointCount ? contour : nil
        } catch {
            return nil
        }
    }

    /// なぞりの内側に見えているインスタンスの番号を集める。
    ///
    /// 移植元はインスタンスマスクのバッファを自前で読んでいましたが、
    /// 新しい Vision には `instanceAtPoint(_:)` があるのでそちらを使います。
    ///
    /// - Important: `Vision.NormalizedPoint` は**左上原点**で、なぞりの座標系と同じです。
    ///   反転は要りません（Vision は歴史的に左下原点の API が多いので、実測して確認しました。
    ///   `SubjectMaskExtractorTests` がこの向きを固定しています）。
    ///   qool にも `NormalizedPoint` があるため、型名を修飾しています。
    private func instancesInsideGuide(of observation: InstanceMaskObservation, guide: [CGPoint]) -> IndexSet {
        let guideBounds = geometry.bounds(for: guide).clampedToUnit()
        var instances = IndexSet()

        for row in 0...Self.guideSampleSteps {
            for column in 0...Self.guideSampleSteps {
                let point = CGPoint(
                    x: guideBounds.minX + guideBounds.width * CGFloat(column) / CGFloat(Self.guideSampleSteps),
                    y: guideBounds.minY + guideBounds.height * CGFloat(row) / CGFloat(Self.guideSampleSteps)
                )

                guard geometry.contains(point, in: guide) else {
                    continue
                }

                instances.formUnion(
                    observation.instanceAtPoint(Vision.NormalizedPoint(x: point.x, y: point.y))
                )
            }
        }

        // **0 は背景です。** `instanceAtPoint` は被写体がない位置でも `[0]` を返すため、
        // 除かないと「なぞりの中に何もない」場合でもマスクを作ってしまいます。
        instances.remove(Self.backgroundInstance)

        return instances
    }

    /// 中心から放射状にレイを飛ばし、**最も遠いマスク上の点**を拾う。
    /// 途中に穴があっても外側の輪郭を取れます。
    private func contourFromMask(_ maskBuffer: CVPixelBuffer, guidedBy guide: [CGPoint]) -> [CGPoint] {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(maskBuffer) else {
            return []
        }

        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(maskBuffer)
        let guideBounds = geometry.bounds(for: guide)
            .insetBy(dx: Self.guideInset, dy: Self.guideInset)
            .clampedToUnit()
        let center = CGPoint(x: guideBounds.midX, y: guideBounds.midY)

        return (0..<Self.rayCount).compactMap { rayIndex in
            let angle = CGFloat(rayIndex) / CGFloat(Self.rayCount) * 2 * .pi
            var bestPoint: CGPoint?

            for step in 0...Self.raySteps {
                let radius = CGFloat(step) / CGFloat(Self.raySteps)
                let point = CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                )

                guard guideBounds.contains(point) else {
                    continue
                }

                let x = min(width - 1, max(0, Int(point.x * CGFloat(width))))
                let y = min(height - 1, max(0, Int(point.y * CGFloat(height))))

                if maskValue(
                    baseAddress: baseAddress,
                    bytesPerRow: bytesPerRow,
                    pixelFormat: pixelFormat,
                    x: x,
                    y: y
                ) > Self.maskThreshold {
                    bestPoint = point
                }
            }

            return bestPoint
        }
    }

    private func maskValue(
        baseAddress: UnsafeMutableRawPointer,
        bytesPerRow: Int,
        pixelFormat: OSType,
        x: Int,
        y: Int
    ) -> Float {
        let row = baseAddress.advanced(by: y * bytesPerRow)

        switch pixelFormat {
        case kCVPixelFormatType_OneComponent32Float:
            return row.assumingMemoryBound(to: Float.self)[x]
        case kCVPixelFormatType_OneComponent8:
            return Float(row.assumingMemoryBound(to: UInt8.self)[x]) / 255
        case kCVPixelFormatType_32BGRA:
            return Float(row.assumingMemoryBound(to: UInt8.self)[x * 4 + 3]) / 255
        default:
            return 0
        }
    }

    private func instanceLabel(
        baseAddress: UnsafeMutableRawPointer,
        bytesPerRow: Int,
        pixelFormat: OSType,
        x: Int,
        y: Int
    ) -> Int {
        let row = baseAddress.advanced(by: y * bytesPerRow)

        switch pixelFormat {
        case kCVPixelFormatType_OneComponent8:
            return Int(row.assumingMemoryBound(to: UInt8.self)[x])
        case kCVPixelFormatType_OneComponent16:
            return Int(row.assumingMemoryBound(to: UInt16.self)[x])
        case kCVPixelFormatType_OneComponent32Float:
            return Int(row.assumingMemoryBound(to: Float.self)[x].rounded())
        default:
            return 0
        }
    }
}
