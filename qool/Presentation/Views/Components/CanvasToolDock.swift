import SwiftUI

/// キャンバス下部のツール選択。
///
/// Liquid Glass は `GlassEffectContainer` の中の兄弟同士が溶け合う設計なので、
/// **ガラスを入れ子にしません。** 選択の移動は `matchedGeometryEffect` ではなく
/// `glassEffectID` に任せ、ガラスが分離・結合する本来の動きに乗せます。
struct CanvasToolDock: View {
    @ObservedObject var viewModel: CanvasViewModel

    @Namespace private var glassNamespace

    private let tools: [CanvasTool] = [.select, .rectangle, .path, .line, .text]

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(tools) { tool in
                    let isSelected = viewModel.selectedTool == tool

                    Button {
                        viewModel.selectTool(tool)
                    } label: {
                        Image(systemName: iconName(for: tool))
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 52, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.78))
                    .glassEffect(
                        isSelected ? .regular.tint(Color.accentColor.opacity(0.18)).interactive() : .regular,
                        in: .capsule
                    )
                    .glassEffectID(tool, in: glassNamespace)
                    .accessibilityLabel(tool.rawValue)
                }
            }
        }
        .glassEffectTransition(.matchedGeometry)
    }

    private func iconName(for tool: CanvasTool) -> String {
        switch tool {
        case .select:
            "cursorarrow"
        case .rectangle:
            "rectangle"
        case .path:
            "point.topleft.down.curvedto.point.bottomright.up"
        case .line:
            "line.diagonal"
        case .text:
            "textformat"
        case .image:
            "photo"
        }
    }
}
