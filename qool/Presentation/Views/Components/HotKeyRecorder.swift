import AppKit
import SwiftUI

/// キーを押して割り当てを決めるボタン。
struct HotKeyRecorder: View {
    let label: String
    /// 記録できる条件を満たさなかったときの理由。`nil` なら受け付けます。
    let validate: (UInt16, HotKeyModifiers) -> String?
    let onRecord: (UInt16, HotKeyModifiers) -> Void

    @State private var isRecording = false
    @State private var rejection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isRecording = true
                rejection = nil
            } label: {
                Text(isRecording ? "キーを押してください" : label)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(minWidth: 120)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? Color.accentColor : nil)
            .background {
                if isRecording {
                    KeyRecorderBridge(
                        onRecord: { keyCode, modifiers in
                            if let reason = validate(keyCode, modifiers) {
                                rejection = reason
                            } else {
                                onRecord(keyCode, modifiers)
                                rejection = nil
                            }

                            isRecording = false
                        },
                        onCancel: { isRecording = false }
                    )
                    .frame(width: 0, height: 0)
                }
            }

            if let rejection {
                Text(rejection)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
            }
        }
    }
}

private struct KeyRecorderBridge: NSViewRepresentable {
    let onRecord: (UInt16, HotKeyModifiers) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyRecordingView {
        let view = KeyRecordingView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        // 生成直後はまだウィンドウに載っていないため、次のループで first responder にします。
        DispatchQueue.main.async { view.beginRecording() }

        return view
    }

    func updateNSView(_ nsView: KeyRecordingView, context: Context) {
        nsView.onRecord = onRecord
        nsView.onCancel = onCancel
    }
}
