import SwiftUI

struct CanvasPropertiesPanel: View {
    @ObservedObject var viewModel: CanvasViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("プロパティ")
                .font(.headline)

            if let element = viewModel.selectedElement {
                propertyContent(for: element)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "cursorarrow.click")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("選択ツールでオブジェクトをクリックすると編集できます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .background {
            Rectangle()
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }

    @ViewBuilder
    private func propertyContent(for element: CanvasElement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(element.kind.displayName)
                .font(.subheadline.weight(.semibold))
            Text("x \(Int(element.frame.minX))  y \(Int(element.frame.minY))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }

        if element.kind == .text {
            VStack(alignment: .leading, spacing: 8) {
                Text("テキスト")
                    .font(.subheadline.weight(.semibold))
                TextField(
                    "テキスト",
                    text: Binding(
                        get: { viewModel.selectedElement?.text ?? "" },
                        set: viewModel.updateText
                    )
                )
                .textFieldStyle(.roundedBorder)
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("塗り")
                .font(.subheadline.weight(.semibold))
            ColorSwatchPicker(
                selectedColor: element.fillColor,
                colors: CanvasColor.fillOptions,
                onSelect: viewModel.updateFillColor
            )
        }

        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "枠線",
                isOn: Binding(
                    get: { viewModel.selectedElement?.showsStroke ?? false },
                    set: viewModel.updateShowsStroke
                )
            )

            if element.showsStroke {
                ColorSwatchPicker(
                    selectedColor: element.strokeColor,
                    colors: CanvasColor.strokeOptions,
                    onSelect: viewModel.updateStrokeColor
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("太さ \(Int(element.strokeWidth))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.selectedElement?.strokeWidth ?? 0) },
                            set: { viewModel.updateStrokeWidth(CGFloat($0)) }
                        ),
                        in: 0...12,
                        step: 1
                    )
                }
            }
        }

        Button(role: .destructive) {
            viewModel.deleteSelectedElement()
        } label: {
            Label("削除", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

private struct ColorSwatchPicker: View {
    let selectedColor: CanvasColor
    let colors: [CanvasColor]
    let onSelect: (CanvasColor) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(colors) { color in
                Button {
                    onSelect(color)
                } label: {
                    Circle()
                        .fill(color.swatchFill)
                        .overlay {
                            Circle()
                                .stroke(Color(.separator), lineWidth: color == .clear ? 1 : 0)
                        }
                        .overlay {
                            if selectedColor == color {
                                Circle()
                                    .stroke(Color.accentColor, lineWidth: 3)
                                    .padding(-4)
                            }
                        }
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.displayName)
            }
        }
    }
}

private extension CanvasElementKind {
    var displayName: String {
        switch self {
        case .rectangle:
            "矩形"
        case .path:
            "パス"
        case .line:
            "直線"
        case .text:
            "テキスト"
        case .imageCutout:
            "画像"
        }
    }
}

private extension CanvasColor {
    static let fillOptions: [CanvasColor] = [.paper, .mint, .coral, .sky, .clear]
    static let strokeOptions: [CanvasColor] = [.ink, .coral, .sky, .mint]

    var swatchFill: Color {
        self == .clear ? Color.white : swiftUIColor
    }
}
