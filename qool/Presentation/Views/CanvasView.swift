import SwiftUI

struct CanvasView: View {
    @ObservedObject var rootViewModel: AppRootViewModel
    @StateObject private var viewModel: CanvasViewModel

    init(memo: Memo, viewModel rootViewModel: AppRootViewModel) {
        self.rootViewModel = rootViewModel
        _viewModel = StateObject(
            wrappedValue: CanvasViewModel(
                memo: memo,
                elementFactory: CanvasElementFactory()
            ) { updatedMemo in
                rootViewModel.saveMemo(updatedMemo)
            }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let usesSideProperties = proxy.size.width >= 820

            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    CanvasSurface(
                        elements: viewModel.memo.canvas.elements,
                        draftElement: viewModel.draftElement,
                        selectedElementID: viewModel.selectedElementID,
                        selectedTool: viewModel.selectedTool,
                        onClearSelection: viewModel.clearSelection,
                        onHitTestElement: viewModel.elementID,
                        onUpdateDraft: viewModel.updateDraft,
                        onCommitDraft: viewModel.commitDraft,
                        onSelectElement: viewModel.selectElement,
                        onMoveSelectedElement: viewModel.moveSelectedElement
                    )
                    .padding(.leading, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 96)
                    .padding(.trailing, usesSideProperties ? 12 : 16)

                    if usesSideProperties {
                        CanvasPropertiesPanel(viewModel: viewModel)
                            .frame(width: 280)
                            .padding(.top, 16)
                            .padding(.trailing, 16)
                            .padding(.bottom, 96)
                    }
                }

                CanvasToolDock(
                    selectedTool: viewModel.selectedTool,
                    onSelectTool: viewModel.selectTool
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(viewModel.memo.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: ImageWorkflowRoute.cutout) {
                    Label("メモに画像を追加", systemImage: "photo.badge.plus")
                }
            }
        }
    }
}
