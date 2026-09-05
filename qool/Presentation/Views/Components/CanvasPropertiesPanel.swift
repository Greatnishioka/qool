import SwiftUI
import AppKit

struct CanvasPropertiesPanel: View {
    @ObservedObject var viewModel: CanvasViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("プロパティ")
                .font(.headline)

            if let element = viewModel.selectedElement {
                propertyContent(for: element)
            } else if viewModel.hasSelection {
                multipleSelectionContent
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
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var multipleSelectionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(viewModel.selectedElementsCount)個のオブジェクト")
                    .font(.subheadline.weight(.semibold))
                Text("複数選択中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.unionSelectedElements()
            } label: {
                Label("結合", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canUnionSelection)

            Button(role: .destructive) {
                viewModel.deleteSelectedElement()
            } label: {
                Label("まとめて削除", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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

        if let sourceElement = viewModel.selectedUnionSource {
            unionSourceContent(for: sourceElement)
        }

        if element.kind == .text {
            VStack(alignment: .leading, spacing: 8) {
                Text("テキスト")
                    .font(.subheadline.weight(.semibold))
                TextField(
                    "テキスト",
                    text: Binding(
                        get: { viewModel.selectedElement?.text ?? "" },
                        set: { viewModel.updateText($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }
        }

        if element.kind == .rectangle {
            VStack(alignment: .leading, spacing: 6) {
                Text("角丸 \(Int(element.cornerRadius))")
                    .font(.subheadline.weight(.semibold))
                Slider(
                    value: Binding(
                        get: { Double(viewModel.selectedElement?.cornerRadius ?? 0) },
                        set: { viewModel.updateCornerRadius(CGFloat($0)) }
                    ),
                    in: 0...Double(max(0, min(element.frame.width, element.frame.height) / 2)),
                    step: 1
                )
            }
        }

        if element.kind == .imageCutout {
            imageAdjustmentContent(for: element)
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("塗り")
                .font(.subheadline.weight(.semibold))
            ColorSwatchPicker(
                selectedColor: element.fillColor,
                onSelect: viewModel.updateFillColor
            )
        }

        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "枠線",
                isOn: Binding(
                    get: { viewModel.selectedElement?.showsStroke ?? false },
                    set: { viewModel.updateShowsStroke($0) }
                )
            )

            if element.showsStroke {
                ColorSwatchPicker(
                    selectedColor: element.strokeColor,
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

        if element.unionSourceElements.isEmpty == false {
            Button {
                viewModel.separateSelectedElement()
            } label: {
                Label("分割", systemImage: "rectangle.on.rectangle.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }

        Button(role: .destructive) {
            viewModel.deleteSelectedElement()
        } label: {
            Label("削除", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    /// 切り抜き画像の見え方（S7）。
    ///
    /// **輪郭ではなく見た目だけを変えます。** 余白とぼかしはマスクを膨らませる方向に効き、
    /// 保存されている輪郭そのものは動きません。やり直しは切り抜き画面の側です。
    @ViewBuilder
    private func imageAdjustmentContent(for element: CanvasElement) -> some View {
        let adjustment = element.imageAdjustment

        VStack(alignment: .leading, spacing: 10) {
            Text("画像の調整")
                .font(.subheadline.weight(.semibold))

            adjustmentSlider(
                title: "不透明度",
                value: Binding(
                    get: { adjustment.opacity },
                    set: { viewModel.updateImageAdjustment(adjustment.updated(opacity: $0)) }
                ),
                range: ImageAdjustment.opacityRange,
                format: { "\(Int($0 * 100))%" }
            )

            adjustmentSlider(
                title: "明るさ",
                value: Binding(
                    get: { adjustment.brightness },
                    set: { viewModel.updateImageAdjustment(adjustment.updated(brightness: $0)) }
                ),
                range: ImageAdjustment.brightnessRange,
                format: { String(format: "%+.2f", $0) }
            )

            adjustmentSlider(
                title: "余白",
                value: Binding(
                    get: { adjustment.padding },
                    set: { viewModel.updateImageAdjustment(adjustment.updated(padding: $0)) }
                ),
                range: ImageAdjustment.paddingRange,
                format: { "\(Int($0))" }
            )

            adjustmentSlider(
                title: "ぼかし",
                value: Binding(
                    get: { adjustment.blur },
                    set: { viewModel.updateImageAdjustment(adjustment.updated(blur: $0)) }
                ),
                range: ImageAdjustment.blurRange,
                format: { "\(Int($0))" }
            )

            if adjustment.blur > 0 {
                Picker(
                    "ぼかす方向",
                    selection: Binding(
                        get: { adjustment.blurDirection },
                        set: { viewModel.updateImageAdjustment(adjustment.updated(blurDirection: $0)) }
                    )
                ) {
                    ForEach(ImageBlurDirection.allCases) { direction in
                        Text(direction.displayName).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
            }

            Button("初期状態に戻す") {
                viewModel.updateImageAdjustment(.default)
            }
            .buttonStyle(.bordered)
            .disabled(adjustment == .default)
        }
    }

    /// `Binding` は呼び出し側で組みます。**閉包を引数で受け渡すと `@Sendable` を要求され、
    /// `viewModel` を捕まえられません。**
    private func adjustmentSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range)
        }
    }

    @ViewBuilder
    private func unionSourceContent(for sourceElement: CanvasElementSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("構成元")
                .font(.subheadline.weight(.semibold))
            Text(sourceElement.kind.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if sourceElement.kind == .rectangle {
            VStack(alignment: .leading, spacing: 6) {
                Text("構成元の角丸 \(Int(sourceElement.cornerRadius))")
                    .font(.subheadline.weight(.semibold))
                Slider(
                    value: Binding(
                        get: { Double(viewModel.selectedUnionSource?.cornerRadius ?? 0) },
                        set: { viewModel.updateSelectedUnionSourceCornerRadius(CGFloat($0)) }
                    ),
                    in: 0...Double(max(0, min(sourceElement.frame.width, sourceElement.frame.height) / 2)),
                    step: 1
                )
            }
        }
    }
}

private struct ColorSwatchPicker: View {
    let selectedColor: CanvasColor
    let onSelect: (CanvasColor) -> Void

    @State private var isCustomPickerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isCustomPickerPresented = true
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedColor.swatchFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        }
                        .frame(width: 34, height: 34)

                    Text(selectedColor.hexLabel)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "eyedropper.halffull")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .tertiarySystemFill))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("カスタムカラー")
            .popover(isPresented: $isCustomPickerPresented, arrowEdge: .trailing) {
                CustomColorPopover(
                    selectedColor: selectedColor,
                    onSelect: onSelect
                )
                .frame(width: 240)
            }
        }
    }
}

private struct CustomColorPopover: View {
    let selectedColor: CanvasColor
    let onSelect: (CanvasColor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("カラー")
                .font(.subheadline.weight(.semibold))

            RoundedRectangle(cornerRadius: 8)
                .fill(selectedColor.swatchFill)
                .frame(height: 52)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }

            ColorPicker(
                "色を選択",
                selection: Binding(
                    get: { selectedColor.swiftUIColor },
                    set: { color in
                        if let converted = CanvasColor.custom(from: color) {
                            onSelect(converted)
                        }
                    }
                ),
                supportsOpacity: true
            )

            Text(selectedColor.hexLabel)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(14)
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
    var swatchFill: Color {
        self == .clear ? Color.white : swiftUIColor
    }

    var hexLabel: String {
        let components = components
        return String(
            format: "#%02X%02X%02X  %.0f%%",
            Int(components.red * 255),
            Int(components.green * 255),
            Int(components.blue * 255),
            components.opacity * 100
        )
    }

    /// sRGB へ変換できない色（動的色・パターン色）では `nil`。
    /// 黒として保存すると色が失われたことに気づけないため、呼び出し側で変更を捨てます。
    static func custom(from color: Color) -> CanvasColor? {
        RGBAComponents(color).map(CanvasColor.custom)
    }
}
