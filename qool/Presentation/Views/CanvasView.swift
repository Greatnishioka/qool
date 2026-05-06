import SwiftUI

struct CanvasView: View {
    let memo: Memo
    @ObservedObject var viewModel: AppRootViewModel
    @State private var selectedTool: CanvasTool = .select

    var body: some View {
        VStack(spacing: 0) {
            toolBar

            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                CanvasSurface(elements: memo.canvas.elements)
                    .padding(16)
            }
        }
        .navigationTitle(memo.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: ImageWorkflowRoute.cutout) {
                    Label("メモに画像を追加", systemImage: "photo.badge.plus")
                }
            }
        }
    }

    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CanvasTool.allCases) { tool in
                    Button {
                        selectedTool = tool
                        viewModel.addElement(using: tool)
                    } label: {
                        Label(tool.rawValue, systemImage: iconName(for: tool))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedTool == tool ? .accentColor : .secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.thinMaterial)
    }

    private func iconName(for tool: CanvasTool) -> String {
        switch tool {
        case .select:
            "cursorarrow"
        case .rectangle:
            "rectangle"
        case .curve:
            "point.topleft.down.curvedto.point.bottomright.up"
        case .textPath:
            "textformat"
        case .image:
            "photo"
        }
    }
}
