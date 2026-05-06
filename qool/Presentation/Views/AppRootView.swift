import SwiftUI

struct AppRootView: View {
    @ObservedObject var viewModel: AppRootViewModel

    var body: some View {
        NavigationStack {
            MemoListView(viewModel: viewModel)
                .navigationDestination(item: $viewModel.selectedMemo) { memo in
                    CanvasView(memo: memo, viewModel: viewModel)
                }
                .navigationDestination(for: ImageWorkflowRoute.self) { route in
                    switch route {
                    case .cutout:
                        ImageCutoutView(viewModel: viewModel)
                    case .adjustment:
                        ImageAdjustmentView(viewModel: viewModel)
                    }
                }
        }
    }
}

enum ImageWorkflowRoute: Hashable {
    case cutout
    case adjustment
}
