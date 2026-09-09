import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 切り抜きマスクと PNG の相互変換。
///
/// **AppKit を使いません。** `NSBitmapImageRep` は色空間の変換を行わないと明記されておらず、
/// 被覆率が保存される保証がありません。ImageIO で完結させます。
///
/// **1 チャンネルで持ちます。** 3 チャンネルにすると容量が 3 倍になるうえ、
/// 色として扱われて値が変わりかねません。
///
/// **画素の並びは「1 行目が上」です。** `CGImage` のバッファはこの並びで、
/// `CutoutMask.coverage` も同じ約束にしています。ここが崩れると上下が裏返ります。
nonisolated struct CutoutMaskPNGCodec {
    init() {}

    func encode(_ mask: CutoutMask) -> Data? {
        guard let image = grayscaleImage(from: mask) else {
            return nil
        }

        let data = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }

    func decode(_ data: Data, extent: CGRect) -> CutoutMask? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        return mask(from: image, extent: extent)
    }

    /// `CGImage` から被覆率を取り出す。
    ///
    /// **1 チャンネル 8bit ならバッファを直接読みます。** 描き直すと色空間の変換が挟まり、
    /// 値が変わり得ます。形式が違うときだけ、灰色のビットマップへ描いて揃えます。
    func mask(from image: CGImage, extent: CGRect) -> CutoutMask? {
        directCoverage(of: image).flatMap { coverage in
            CutoutMask(extent: extent, width: image.width, height: image.height, coverage: coverage)
        } ?? redrawnMask(from: image, extent: extent)
    }

    private func directCoverage(of image: CGImage) -> [UInt8]? {
        guard image.bitsPerComponent == 8,
              image.bitsPerPixel == 8,
              image.colorSpace?.model == .monochrome,
              image.alphaInfo == .none,
              let data = image.dataProvider?.data as Data? else {
            return nil
        }

        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow

        guard data.count >= bytesPerRow * height else {
            return nil
        }

        // **行の余白を落とします。** `bytesPerRow` は幅より広いことがあります。
        guard bytesPerRow != width else {
            return Array(data)
        }

        var coverage: [UInt8] = []
        coverage.reserveCapacity(width * height)

        for row in 0..<height {
            let start = row * bytesPerRow
            coverage.append(contentsOf: data[start..<(start + width)])
        }

        return coverage
    }

    private func redrawnMask(from image: CGImage, extent: CGRect) -> CutoutMask? {
        let width = image.width
        let height = image.height

        guard let (pixelCount, overflowed) = Optional(width.multipliedReportingOverflow(by: height)),
              !overflowed else {
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

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            return true
        }

        guard drawn else {
            return nil
        }

        return CutoutMask(extent: extent, width: width, height: height, coverage: coverage)
    }

    /// 1 チャンネルの画像。保存にも描画のマスクにも使います。
    ///
    /// **不透明度ではなく明るさで持ちます。** 不透明度だけの画像は色空間を
    /// 持たない指定が要り、Swift の `CGImage` の初期化子では作れません。
    /// 描画側が `luminanceToAlpha()` で明るさを不透明度へ読み替えます。
    func grayscaleImage(from mask: CutoutMask) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(mask.coverage) as CFData) else {
            return nil
        }

        return CGImage(
            width: mask.width,
            height: mask.height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: mask.width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
