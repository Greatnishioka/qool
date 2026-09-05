import CoreGraphics

/// 元画像から切り出す範囲。
nonisolated struct CutoutCrop: Equatable {
    /// 切り出す画素の範囲。画素の格子に載っています。
    let pixelRect: CGRect

    let normalizedRect: CGRect
}
