import CoreGraphics

/// 描画に使うマスク。膨らませたあとの形なので、覆う範囲も元とは違います。
struct CutoutDrawingMask {
    let image: CGImage
    let extent: CGRect
}
