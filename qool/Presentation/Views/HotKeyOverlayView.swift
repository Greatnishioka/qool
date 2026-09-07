import SwiftUI

/// プレフィックスを押した直後に出る割り当て一覧。
///
/// **覚えていなくても使える状態にするために出します**（Vim の which-key と同じ考え方）。
struct HotKeyOverlayView: View {

    private static let shadowMargin: CGFloat = 56
    private static let cornerRadius: CGFloat = 20

    let prefix: HotKeyShortcut
    let bindings: [HotKeyBinding]

    var body: some View {
        GlassEffectContainer {
            content
                .padding(18)
                .glassEffect(in: .rect(cornerRadius: Self.cornerRadius))
                // 2 枚重ねます。1 枚だと、濃さが足りないか広がりすぎるかのどちらかになります。
                // 広く薄い影で落ち方をなだらかにし、狭く濃い影で縁を締めます。
                .shadow(color: .black.opacity(0.10), radius: 16, y: 5)
                .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
        }
        .padding(Self.shadowMargin)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prefix.displayName)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            ForEach(bindings, id: \.keyCode) { binding in
                HStack(spacing: 12) {
                    Text(VirtualKey.symbol(forKeyCode: binding.keyCode))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(minWidth: 26, minHeight: 26)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    Text(binding.action.displayName)
                        .font(.system(size: 13))
                }
            }

            Text("esc で閉じる")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}
