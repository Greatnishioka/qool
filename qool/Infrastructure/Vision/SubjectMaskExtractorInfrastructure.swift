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
///
/// **しきい値を掛けずにマスクを返します。** Vision の前景マスクは 0〜1 の連続値で、
/// 2 値に潰すと縁の半透明が失われます。髪の毛やガラスを抜けるかどうかはここで決まります
/// （[設計](https://github.com/Greatnishioka/qool/issues/12)）。
nonisolated struct SubjectMaskExtractorInfrastructure: CutoutMaskExtractorProtocol {
    /// なぞりの内側を何分割して調べるか。全画素を見る必要はありません。
    private static let guideSampleSteps = 40
    /// `instanceAtPoint` が背景に対して返す番号。
    private static let backgroundInstance = 0

    private let geometry = ContourGeometry()

    init() {}

    func extractMask(in image: CGImage, guidedBy guide: [CGPoint]) async -> CutoutMask? {
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

            return cutoutMask(
                from: try observation.generateScaledMask(for: instances, scaledToImageFrom: handler)
            )
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

    /// マスクの画素をそのまま被覆率として読み取る。
    ///
    /// **画像の全体を覆います。** 画像は要素の枠いっぱいに描かれるので、
    /// 単位矩形をそのまま覆う範囲にできます。使っていない縁は呼び出し側が切り詰めます。
    private func cutoutMask(from buffer: CVPixelBuffer) -> CutoutMask? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)

        guard width > 0, height > 0 else {
            return nil
        }

        var coverage = [UInt8](repeating: 0, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let value = maskValue(
                    baseAddress: baseAddress,
                    bytesPerRow: bytesPerRow,
                    pixelFormat: pixelFormat,
                    x: x,
                    y: y
                )

                coverage[y * width + x] = UInt8(min(255, max(0, value * 255)))
            }
        }

        return CutoutMask(width: width, height: height, coverage: coverage)
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
}
