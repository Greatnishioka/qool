import CoreGraphics
import Foundation

/// 切り抜きマスクを復号して保持する。
///
/// **`body` から復号を追い出すためにあります。** SwiftUI の `body` はドラッグ中に毎フレーム走るため、
/// そこで PNG を復号すると描画が破綻します。[CanvasImageStore](CanvasImageStore.swift) と同じ役割です。
///
/// **符号化は持ちません。** PNG との変換は
/// [CutoutMaskPNGCodec](../../Infrastructure/Persistence/CutoutMaskPNGCodec.swift) の仕事です。
/// ここは表示のための持ち回しだけを担います。
@MainActor
final class CutoutMaskStore {
    /// 抱えてよい画素数のおおよその上限。
    ///
    /// **上限が無いとメモを見て回るだけで増え続けます。** 長辺 2048 のマスクが
    /// 1 枚 4MiB 程度なので、その数枚ぶんに収めます。
    static let defaultCostLimit = 64 * 1024 * 1024

    private let repository: any ImageAssetRepositoryProtocol
    private let codec: CutoutMaskPNGCodec
    private let filters = CutoutMaskFilters()
    private let cache = NSCache<NSString, CachedMask>()
    /// 膨らませた結果。余白の値ごとに別物なので分けて持ちます。
    private let dilatedCache = NSCache<NSString, CachedMask>()

    init(
        repository: any ImageAssetRepositoryProtocol,
        codec: CutoutMaskPNGCodec = CutoutMaskPNGCodec(),
        costLimit: Int = CutoutMaskStore.defaultCostLimit
    ) {
        self.repository = repository
        self.codec = codec
        cache.totalCostLimit = costLimit
        dilatedCache.totalCostLimit = costLimit
    }

    func mask(for reference: CutoutMaskReference, in memoID: Memo.ID) -> CutoutMask? {
        cached(for: reference, in: memoID)?.mask
    }

    /// 描画に使うマスク。**余白のぶん膨らませた形**を返します。
    ///
    /// **膨張はここで一度だけ行い、結果を持ちます。** `body` の中で計算すると、
    /// ドラッグ中に毎フレーム画素をなめることになります。
    func drawingMask(for element: CanvasElement, in memoID: Memo.ID) -> CutoutDrawingMask? {
        guard let reference = element.cutoutMask,
              let mask = mask(for: reference, in: memoID) else {
            return nil
        }

        let adjustment = element.imageAdjustment
        // 外側ぼかしは、ぼけた分だけ形が外へ出ます。内側ぼかしは輪郭の内側で完結します。
        let outset = CGFloat(adjustment.padding + (adjustment.blurDirection == .inward ? 0 : adjustment.blur))
        let radius = filters.radius(forPointPadding: outset, mask: mask, elementSize: element.frame.size)

        guard radius.x > 0 || radius.y > 0 else {
            return cached(for: reference, in: memoID)?.image.map {
                CutoutDrawingMask(image: $0, extent: mask.extent)
            }
        }

        let key = Self.key(for: reference, in: memoID, radius: radius) as NSString

        if let cached = dilatedCache.object(forKey: key) {
            return cached.image.map { CutoutDrawingMask(image: $0, extent: cached.mask.extent) }
        }

        guard let dilated = filters.dilated(mask, radiusX: radius.x, radiusY: radius.y) else {
            return nil
        }

        let entry = CachedMask(mask: dilated, image: codec.grayscaleImage(from: dilated))
        dilatedCache.setObject(entry, forKey: key, cost: dilated.coverage.count * 2)

        return entry.image.map { CutoutDrawingMask(image: $0, extent: dilated.extent) }
    }

    func removeAll() {
        cache.removeAllObjects()
        dilatedCache.removeAllObjects()
    }

    private func cached(for reference: CutoutMaskReference, in memoID: Memo.ID) -> CachedMask? {
        let key = Self.key(for: reference, in: memoID)

        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let data = repository.data(for: reference.assetID, in: memoID),
              let mask = codec.decode(data, extent: reference.extent) else {
            return nil
        }

        let entry = CachedMask(mask: mask, image: codec.grayscaleImage(from: mask))
        // 被覆率の配列と、画像が持つ複製の 2 つぶんを数えます。
        cache.setObject(entry, forKey: key, cost: mask.coverage.count * 2)

        return entry
    }

    /// **`extent` とメモまで含めた鍵にします。**
    /// 同じ画像を別の範囲で参照したときに、先に読んだほうが返り続けるためです。
    /// アセットはメモに属するので、メモが違えば別物として扱います。
    private static func key(for reference: CutoutMaskReference, in memoID: Memo.ID) -> NSString {
        let extent = reference.extent

        return """
        \(memoID.uuidString)/\(reference.assetID.uuidString)/\
        \(extent.minX),\(extent.minY),\(extent.width),\(extent.height)
        """ as NSString
    }

    /// 膨らませた結果の鍵。半径まで含めないと、余白を変えても古い形が返ります。
    private static func key(
        for reference: CutoutMaskReference,
        in memoID: Memo.ID,
        radius: (x: Int, y: Int)
    ) -> String {
        "\(key(for: reference, in: memoID))/\(radius.x)x\(radius.y)"
    }
}

private final class CachedMask {
    let mask: CutoutMask
    let image: CGImage?

    init(mask: CutoutMask, image: CGImage?) {
        self.mask = mask
        self.image = image
    }
}


/// 描画に使うマスク。膨らませたあとの形なので、覆う範囲も元とは違います。
struct CutoutDrawingMask {
    let image: CGImage
    let extent: CGRect
}
