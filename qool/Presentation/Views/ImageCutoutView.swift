import SwiftUI

struct ImageCutoutView: View {
    @ObservedObject var viewModel: AppRootViewModel
    @State private var pathPoints: [NormalizedPoint] = [
        NormalizedPoint(x: 0.22, y: 0.26),
        NormalizedPoint(x: 0.76, y: 0.22),
        NormalizedPoint(x: 0.82, y: 0.72),
        NormalizedPoint(x: 0.28, y: 0.78)
    ]

    var body: some View {
        VStack(spacing: 16) {
            CutoutPreview(pathPoints: pathPoints)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            VStack(alignment: .leading, spacing: 10) {
                Text("画像切り抜き")
                    .font(.headline)
                Text("画像をパスで囲い、メモ化する範囲を決めます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            NavigationLink(value: ImageWorkflowRoute.adjustment) {
                Label("メモ化", systemImage: "scissors")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)

            Spacer()
        }
        .navigationTitle("画像切り抜き")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.cutoutDraft.pathPoints = pathPoints
        }
    }
}
