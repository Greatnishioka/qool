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
    private let cache = NSCache<NSString, CachedMask>()

    init(
        repository: any ImageAssetRepositoryProtocol,
        codec: CutoutMaskPNGCodec = CutoutMaskPNGCodec(),
        costLimit: Int = CutoutMaskStore.defaultCostLimit
    ) {
        self.repository = repository
        self.codec = codec
        cache.totalCostLimit = costLimit
    }

    func mask(for reference: CutoutMaskReference, in memoID: Memo.ID) -> CutoutMask? {
        cached(for: reference, in: memoID)?.mask
    }

    /// 描画で使うマスク画像。被覆率をそのまま濃さとして持つ 1 チャンネルの画像です。
    func image(for reference: CutoutMaskReference, in memoID: Memo.ID) -> CGImage? {
        cached(for: reference, in: memoID)?.image
    }

    func removeAll() {
        cache.removeAllObjects()
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
}

private final class CachedMask {
    let mask: CutoutMask
    let image: CGImage?

    init(mask: CutoutMask, image: CGImage?) {
        self.mask = mask
        self.image = image
    }
}
