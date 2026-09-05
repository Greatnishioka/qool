import SwiftUI
import UniformTypeIdentifiers

struct CanvasView: View {
    @StateObject private var viewModel: CanvasViewModel
    @State private var isImportingImage = false
    /// 切り抜きシートの対象。開いた時点の要素を持ちます。
    @State private var cutoutTarget: CanvasElement?
    /// 直近のキャンバスの大きさ。ツールバーからの取り込みは中央に置くため、これが要ります。
    @State private var canvasSize: CGSize = .zero

    /// 画像を持つ要素が 1 つだけ選ばれているときにだけ切り抜けます。
    private var canCutOutSelection: Bool {
        guard let element = viewModel.selectedElement else {
            return false
        }

        return element.kind == .imageCutout && viewModel.image(for: element) != nil
    }

    private var importDropCenter: CGPoint {
        CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    }

    /// ルートの ViewModel は保存の宛先としてしか使わないため、監視しません。
    /// `@ObservedObject` にすると、一覧が更新されるたびにキャンバス全体が再評価されます。
    init(memo: Memo, rootViewModel: AppRootViewModel) {
        _viewModel = StateObject(
            wrappedValue: CanvasViewModel(
                memo: memo,
                imageStore: rootViewModel.imageStore,
                importImageUseCase: rootViewModel.importImageUseCase
            ) { updatedMemo in
                Task { await rootViewModel.saveMemo(updatedMemo) }
            }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let usesSideProperties = proxy.size.width >= 820

            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    CanvasSurface(viewModel: viewModel, canvasSize: $canvasSize)
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

                CanvasToolDock(viewModel: viewModel)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle(viewModel.memo.title)
        .toolbar {
            ToolbarItem {
                Button {
                    isImportingImage = true
                } label: {
                    Label("画像を追加", systemImage: "photo.badge.plus")
                }
            }

            ToolbarItem {
                Button {
                    cutoutTarget = viewModel.selectedElement
                } label: {
                    Label("切り抜く", systemImage: "scissors")
                }
                .disabled(!canCutOutSelection)
            }
        }
        .sheet(item: $cutoutTarget) { element in
            if let image = viewModel.image(for: element) {
                ImageCutoutView(
                    image: image,
                    existingContours: element.pathContours,
                    makeContours: viewModel.cutoutPreview,
                    onApply: { viewModel.applyCutout(tracePoints: $0, to: element.id) },
                    onClear: { viewModel.clearCutout(of: element.id) },
                    onDismiss: { cutoutTarget = nil }
                )
            }
        }
        .fileImporter(
            isPresented: $isImportingImage,
            allowedContentTypes: [.image]
        ) { result in
            guard case let .success(url) = result else {
                return
            }

            // ファイル選択で開いた URL は保護されているため、読む間だけ権限を開きます。
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer {
                if needsAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            viewModel.importImage(from: url, at: importDropCenter, canvasSize: canvasSize)
        }
    }
}
