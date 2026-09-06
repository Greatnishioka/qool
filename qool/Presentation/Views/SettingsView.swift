import SwiftUI

/// 設定画面。
///
/// **ホットキーの記録 UI を自作しているのが要点です。** ライブラリ付属の画面をそのまま置くと、
/// プレフィックス方式（2 ストローク）を説明できません。
struct SettingsView: View {
    static let windowID = "settings"

    private static let historyLimitRange =
        Double(ContourEditHistory.limitRange.lowerBound)...Double(ContourEditHistory.limitRange.upperBound)

    @ObservedObject var hotKeys: HotKeyCoordinator
    let settings: any AppSettingsProtocol

    /// 設定は `UserDefaults` 側が正で、この画面は写しを持ちます。
    /// **`AppSettingsProtocol` は監視できない**（`ObservableObject` ではない）ためです。
    @State private var editHistoryLimit: Int
    @State private var isShowingHistoryNote = false

    init(hotKeys: HotKeyCoordinator, settings: any AppSettingsProtocol) {
        self.hotKeys = hotKeys
        self.settings = settings
        _editHistoryLimit = State(initialValue: settings.editHistoryLimit)
    }

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

            Section("切り抜きの手直し") {
                LabeledContent("戻せる手数") {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { Double(editHistoryLimit) },
                                set: { newValue in
                                    editHistoryLimit = Int(newValue.rounded())
                                    settings.editHistoryLimit = editHistoryLimit
                                }
                            ),
                            in: Self.historyLimitRange
                        )
                        .frame(width: 160)

                        Text("\(editHistoryLimit)")
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                Text("履歴は切り抜きシートを開いている間だけ持ちます。閉じると消えます。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text("手数が上限に届く前でも、履歴の合計が \(ContourEditHistory.maximumTotalBytes / 1024 / 1024)MB を超えると古いほうから捨てます。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Section {
                Button("ホットキーを初期値に戻す") {
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
        .frame(width: 460, height: 520)
    }
}
