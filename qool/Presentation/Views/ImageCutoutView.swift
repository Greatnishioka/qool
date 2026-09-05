import AppKit
import SwiftUI

/// S6 画像切り抜き。画像の外周をなぞって輪郭を決めるシートです。
///
/// **正確になぞる必要はありません。** なぞりは `ContourSmoother` が整えるための下地で、
/// トゲが取れ、直線は直線に寄り、角は残ります。
///
/// 輪郭候補の自動抽出（被写体マスクなど）はまだ移植していないため、
/// ここで扱うのは**手描きのなぞりだけ**です。
struct ImageCutoutView: View {
    /// 前の点からこれ以下しか動いていない点は捨てる（正規化距離）。
    /// 間引かないと 1 回のドラッグで数千点になり、平滑化が重くなります。
    private static let minimumTraceSpacing: CGFloat = 0.006

    let image: NSImage
    let existingContours: [CanvasPathContour]
    let makeContours: ([CGPoint]) -> [CanvasPathContour]
    let onApply: ([CGPoint]) -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    @State private var tracePoints: [CGPoint] = []

    private var previewContours: [CanvasPathContour] {
        tracePoints.isEmpty ? existingContours : makeContours(tracePoints)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            preview

            Divider()

            footer
        }
        .frame(width: 860, height: 640)
    }

    private var header: some View {
        HStack {
            Text("画像を切り抜く")
                .font(.system(size: 13, weight: .bold))

            Spacer()

            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var hint: String {
        if tracePoints.isEmpty {
            return existingContours.isEmpty
                ? "画像の上をドラッグして、切り抜きたい範囲を囲みます"
                : "現在の輪郭を表示しています。ドラッグでなぞり直せます"
        }

        return "指を離すと輪郭に整えます。やり直すには「なぞり直す」"
    }

    private var preview: some View {
        GeometryReader { proxy in
            let rect = imageRect(in: proxy.size)

            ZStack(alignment: .topLeading) {
                Color(nsColor: .windowBackgroundColor)

                Image(nsImage: image)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                // なぞり中は画像を少し落として、線を見やすくします。
                if !tracePoints.isEmpty {
                    Color.black.opacity(0.06)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                contourOverlay(in: rect)
                traceOverlay(in: rect)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        appendTracePoint(value.location, in: rect)
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func contourOverlay(in rect: CGRect) -> some View {
        if !previewContours.isEmpty {
            path(for: previewContours, in: rect)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func traceOverlay(in rect: CGRect) -> some View {
        if tracePoints.count >= 2 {
            tracePath(in: rect)
                .stroke(Color.accentColor.opacity(0.45), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("キャンセル", action: onDismiss)

            if !existingContours.isEmpty, tracePoints.isEmpty {
                Button("切り抜きを解除") {
                    onClear()
                    onDismiss()
                }
            }

            Spacer()

            Button("なぞり直す") {
                tracePoints = []
            }
            .disabled(tracePoints.isEmpty)

            Button("適用") {
                onApply(tracePoints)
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(makeContours(tracePoints).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 座標

    /// 画像を aspect-fit で収めた矩形。なぞりの正規化はここを基準にします。
    private func imageRect(in size: CGSize) -> CGRect {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }

        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        return CGRect(
            x: (size.width - fittedSize.width) / 2,
            y: (size.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    /// 画像の外はなぞりに含めません。輪郭が画像からはみ出すと、マスクが破綻します。
    private func appendTracePoint(_ location: CGPoint, in rect: CGRect) {
        guard rect.contains(location), rect.width > 0, rect.height > 0 else {
            return
        }

        let point = CGPoint(
            x: (location.x - rect.minX) / rect.width,
            y: (location.y - rect.minY) / rect.height
        )

        if let lastPoint = tracePoints.last,
           hypot(point.x - lastPoint.x, point.y - lastPoint.y) <= Self.minimumTraceSpacing {
            return
        }

        tracePoints.append(point)
    }

    private func path(for contours: [CanvasPathContour], in rect: CGRect) -> Path {
        var path = Path()

        for contour in contours where contour.points.count >= 2 {
            let points = contour.points.map { point in
                CGPoint(x: rect.minX + rect.width * point.x, y: rect.minY + rect.height * point.y)
            }

            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }

        return path
    }

    private func tracePath(in rect: CGRect) -> Path {
        var path = Path()
        let points = tracePoints.map { point in
            CGPoint(x: rect.minX + rect.width * point.x, y: rect.minY + rect.height * point.y)
        }

        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        return path
    }
}
