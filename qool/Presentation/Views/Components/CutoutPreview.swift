import SwiftUI

struct CutoutPreview: View {
    let pathPoints: [NormalizedPoint]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))

                Image(systemName: "photo")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)

                normalizedPath(in: proxy.size)
                    .fill(Color.accentColor.opacity(0.24))

                normalizedPath(in: proxy.size)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
            }
        }
    }

    private func normalizedPath(in size: CGSize) -> Path {
        var path = Path()
        guard let first = pathPoints.first else {
            return path
        }

        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
        for point in pathPoints.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        path.closeSubpath()
        return path
    }
}
