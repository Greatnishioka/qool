import SwiftUI

/// ホットキーの設定画面。
///
/// **記録 UI を自作しているのが要点です。** ライブラリ付属の画面をそのまま置くと、
/// プレフィックス方式（2 ストローク）を説明できません。
struct HotKeySettingsView: View {
    static let windowID = "hotkey-settings"

    @ObservedObject var hotKeys: HotKeyCoordinator

    var body: some View {
        Form {
            Section("呼び出しキー") {
                LabeledContent("プレフィックス") {
                    HotKeyRecorder(
                        label: hotKeys.configuration.prefix.displayName,
                        validate: { hotKeys.prefixRejection(keyCode: $0, modifiers: $1) },
                        onRecord: { hotKeys.updatePrefix(keyCode: $0, modifiers: $1) }
                    )
                }

                Text("プレフィックスを押して離してから、下のキーを押します。同時押しではありません。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("2 打目の割り当て") {
                ForEach(HotKeyAction.allCases, id: \.self) { action in
                    LabeledContent(action.displayName) {
                        HotKeyRecorder(
                            label: hotKeys.keyCode(for: action).map(VirtualKey.symbol(forKeyCode:)) ?? "未割り当て",
                            validate: { keyCode, _ in hotKeys.bindingRejection(keyCode: keyCode, for: action) },
                            onRecord: { keyCode, _ in hotKeys.updateBinding(keyCode: keyCode, for: action) }
                        )
                    }
                }
            }

            Section {
                Button("初期値に戻す") {
                    hotKeys.resetConfiguration()
                }

                if let message = hotKeys.registrationFailureMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 400)
    }
}
