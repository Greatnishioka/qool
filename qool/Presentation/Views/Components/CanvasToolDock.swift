import SwiftUI

struct CanvasToolDock: View {
    let selectedTool: CanvasTool
    let onSelectTool: (CanvasTool) -> Void

    @Namespace private var selectionNamespace

    private let tools: [CanvasTool] = [.select, .rectangle, .path, .line, .text]

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(tools) { tool in
                    let isSelected = selectedTool == tool

                    Button {
                        withAnimation(.smooth(duration: 0.28, extraBounce: 0.18)) {
                            onSelectTool(tool)
                        }
                    } label: {
                        Image(systemName: iconName(for: tool))
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 52, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.78))
                    .background {
                        if isSelected {
                            Capsule()
                                .glassEffect(.regular.tint(Color.accentColor.opacity(0.18)).interactive(), in: Capsule())
                                .matchedGeometryEffect(id: "selectedToolHighlight", in: selectionNamespace)
                        }
                    }
                    .accessibilityLabel(tool.rawValue)
                }
            }
        }
        .padding(6)
        .glassEffect(.regular.interactive(), in: Capsule())
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
