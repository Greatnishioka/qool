import SwiftUI

/// 選んだ範囲に書式を付けるための、その場に浮く道具。
///
/// **選択の近くに出します。** プロパティパネルへ置くと、書いている場所から目が離れます
/// （[#21](https://github.com/Greatnishioka/qool/issues/21)）。
struct RichTextToolbar: View {
    /// 選べる色。**少なく決め打ちます。** 色を選ぶ画面をここに載せると、
    /// 書いている流れが止まります。
    static let colors: [(name: String, components: RGBAComponents)] = [
        ("赤", RGBAComponents(red: 0.87, green: 0.19, blue: 0.28)),
        ("青", RGBAComponents(red: 0.18, green: 0.45, blue: 0.88)),
        ("緑", RGBAComponents(red: 0.15, green: 0.6, blue: 0.36)),
        ("橙", RGBAComponents(red: 0.93, green: 0.55, blue: 0.13))
    ]

    let onStyle: (InlineMarkdownStyle) -> Void
    let onColor: (RGBAComponents?) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(InlineMarkdownStyle.allCases) { style in
                Button {
                    onStyle(style)
                } label: {
                    Image(systemName: style.systemImage)
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(style.displayName)
            }

            Divider().frame(height: 16)

            ForEach(Self.colors, id: \.name) { color in
                Button {
                    onColor(color.components)
                } label: {
                    Circle()
                        .fill(color.components.swiftUIColor)
                        .frame(width: 13, height: 13)
                        .padding(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(color.name)
            }

            Button {
                onColor(nil)
            } label: {
                Image(systemName: "drop.triangle")
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("色を戻す")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.12)))
        .shadow(radius: 6, y: 2)
    }
}
