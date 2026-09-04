import AppKit

/// 画像アセットを復号して保持する。
///
/// **`body` から復号を追い出すためにあります。** SwiftUI の `body` はドラッグ中に毎フレーム走るため、
/// そこで PNG を復号すると描画が破綻します。
///
/// **無効化は要りません。** `ImageAssetRepositoryProtocol.save` は毎回新しい ID を振るので、
/// 一度読んだ ID の中身が変わることはありません。
/// 値が変わらないため `ObservableObject` にもしていません（監視するものがない）。
@MainActor
final class CanvasImageStore {
    private let repository: any ImageAssetRepositoryProtocol
    private var images: [UUID: NSImage] = [:]

    init(repository: any ImageAssetRepositoryProtocol) {
        self.repository = repository
    }

    func image(for id: UUID, in memoID: Memo.ID) -> NSImage? {
        if let cached = images[id] {
            return cached
        }

        guard let data = repository.data(for: id, in: memoID),
              let image = NSImage(data: data) else {
            return nil
        }

        images[id] = image

        return image
    }

    /// `NSImage` を保存できる形（PNG）へ変換する。変換できなければ `nil`。
    static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
