import CoreGraphics
import Foundation

/// 角を掴んで要素の大きさを変える。
///
/// **既定では縦横比を保ちません。** Photoshop の自由変形と同じで、掴んだ角の対角を
/// 固定したまま縦と横が独立に伸び縮みします。⇧ を押している間だけ比を保ちます。
///
/// **回転したまま変形します。** 伸ばす向きは画面の縦横ではなく要素自身の軸なので、
/// 斜めに置いた要素も、見たとおりの向きに伸びます。
nonisolated struct ResizeCanvasElementUseCase {
    /// これより小さくはしません。0 になると角を掴み直せなくなります。
    static let minimumSize: CGFloat = 8

    /// 角として掴める範囲（掴んだ点から角までの距離）。
    static let handleTolerance: CGFloat = 10

    init() {}

    /// 掴んだ角を `point` まで動かしたときの新しい枠。
    ///
    /// - Parameter preservingAspectRatio: 元の縦横比を保つか（⇧ を押している間）。
    func callAsFunction(
        _ element: CanvasElement,
        corner: CanvasResizeCorner,
        to point: CGPoint,
        preservingAspectRatio: Bool = false
    ) -> CGRect {
        let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
        let radians = element.rotationAngleDegrees * .pi / 180

        // 固定する角の、画面上での位置。
        let anchor = rotated(corner.opposite.point(in: element.frame), around: center, by: radians)

        // 固定した角から掴んだ点までを、要素の座標系へ戻します。
        let dragged = rotated(
            CGPoint(x: point.x - anchor.x, y: point.y - anchor.y),
            around: .zero,
            by: -radians
        )
        let diagonal = preservingAspectRatio ? aspectLocked(dragged, in: element.frame) : dragged

        let width = max(Self.minimumSize, abs(diagonal.x))
        let height = max(Self.minimumSize, abs(diagonal.y))
        // 対角を越えて引いても潰れないよう、向きだけ残します。
        let signedDiagonal = CGPoint(
            x: diagonal.x < 0 ? -width : width,
            y: diagonal.y < 0 ? -height : height
        )

        // 新しい中心は、固定した角から対角の半分だけ進んだところ。
        let half = rotated(CGPoint(x: signedDiagonal.x / 2, y: signedDiagonal.y / 2), around: .zero, by: radians)

        return CGRect(
            x: anchor.x + half.x - width / 2,
            y: anchor.y + half.y - height / 2,
            width: width,
            height: height
        )
    }

    /// 縦横比を保ったときの対角ベクトル。
    ///
    /// **伸びが大きいほうの軸に合わせます。** 小さいほうに合わせると、
    /// 指を遠ざけているのに縮む向きが出て、掴んでいる感じがなくなります。
    private func aspectLocked(_ diagonal: CGPoint, in frame: CGRect) -> CGPoint {
        guard frame.width > 0, frame.height > 0 else {
            return diagonal
        }

        // 倍率で下限を掛けます。幅と高さを別々に丸めると比が崩れます。
        let minimumScale = max(Self.minimumSize / frame.width, Self.minimumSize / frame.height)
        let scale = max(
            minimumScale,
            max(abs(diagonal.x) / frame.width, abs(diagonal.y) / frame.height)
        )

        return CGPoint(
            x: (diagonal.x < 0 ? -1 : 1) * frame.width * scale,
            y: (diagonal.y < 0 ? -1 : 1) * frame.height * scale
        )
    }

    /// `point` が掴んでいる角。どの角でもなければ `nil`。
    ///
    /// **回転を戻してから比べます。** 画面上の四隅と比べると、
    /// 斜めに置いた要素の角を掴めません。
    func corner(
        at point: CGPoint,
        of element: CanvasElement,
        tolerance: CGFloat = ResizeCanvasElementUseCase.handleTolerance
    ) -> CanvasResizeCorner? {
        let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
        let radians = element.rotationAngleDegrees * .pi / 180
        let localPoint = rotated(point, around: center, by: -radians)

        return CanvasResizeCorner.allCases
            .map { corner in (corner, distance(localPoint, corner.point(in: element.frame))) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?
            .0
    }

    private func rotated(_ point: CGPoint, around center: CGPoint, by radians: Double) -> CGPoint {
        guard radians != 0 else {
            return point
        }

        let cosine = cos(radians)
        let sine = sin(radians)
        let dx = point.x - center.x
        let dy = point.y - center.y

        return CGPoint(
            x: center.x + dx * cosine - dy * sine,
            y: center.y + dx * sine + dy * cosine
        )
    }

    private func distance(_ point: CGPoint, _ other: CGPoint) -> CGFloat {
        hypot(point.x - other.x, point.y - other.y)
    }
}
