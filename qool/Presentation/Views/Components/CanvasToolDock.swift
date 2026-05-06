import SwiftUI

struct CanvasToolDock: View {
    let selectedTool: CanvasTool
    let onSelectTool: (CanvasTool) -> Void

    private let tools: [CanvasTool] = [.select, .rectangle, .path, .line, .text]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tools) { tool in
                Button {
                    onSelectTool(tool)
                } label: {
                    Image(systemName: iconName(for: tool))
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 48, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTool == tool ? Color.white : Color.primary)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedTool == tool ? Color.accentColor : Color.clear)
                }
                .accessibilityLabel(tool.rawValue)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
        }
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
