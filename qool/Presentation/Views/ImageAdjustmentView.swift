import SwiftUI

struct ImageAdjustmentView: View {
    @ObservedObject var viewModel: AppRootViewModel
    @State private var adjustment = ImageAdjustment.default
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            CutoutPreview(pathPoints: viewModel.cutoutDraft.pathPoints)
                .opacity(adjustment.opacity)
                .brightness(adjustment.brightness)
                .blur(radius: adjustment.blur)
                .padding(adjustment.padding)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            VStack(spacing: 16) {
                AdjustmentSlider(title: "透明度", value: $adjustment.opacity, range: 0.2...1)
                AdjustmentSlider(title: "明度", value: $adjustment.brightness, range: -0.3...0.3)
                AdjustmentSlider(title: "余白", value: $adjustment.padding, range: 0...36)
                AdjustmentSlider(title: "ぼかし", value: $adjustment.blur, range: 0...8)
            }
            .padding(.horizontal, 20)

            Button {
                viewModel.updateAdjustment(adjustment)
                viewModel.commitImageMemo()
                dismiss()
            } label: {
                Label("キャンバスへ追加", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)

            Spacer()
        }
        .navigationTitle("画像調整")
        .navigationBarTitleDisplayMode(.inline)
    }
}
