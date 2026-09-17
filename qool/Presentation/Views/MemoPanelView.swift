import AppKit
import SwiftUI

/// メモパネル。メニューバーから開く、アプリの中心となる画面。
struct MemoPanelView: View {
    @ObservedObject var viewModel: AppRootViewModel
    let floatingMemos: FloatingMemoPresenter
    @ObservedObject var hotKeys: HotKeyCoordinator
    @Environment(\.openWindow) private var openWindow

    /// 削除は取り消せないので、確認を挟みます。
    @State private var memoPendingDeletion: Memo?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 失敗しているときだけ出る。常時は何も足しません。
            if viewModel.persistenceStatus != .ok {
                statusBanner
                Divider()
            }

            if let message = hotKeys.registrationFailureMessage {
                hotKeyFailureBanner(message)
                Divider()
            }

            header

            Divider()

            content

            Divider()

            footer
        }
        .frame(width: 320, height: 420)
        .confirmationDialog(
            "「\(memoPendingDeletion?.title ?? "")」を削除しますか？",
            isPresented: Binding(
                get: { memoPendingDeletion != nil },
                set: { if !$0 { memoPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                guard let memo = memoPendingDeletion else {
                    return
                }

                memoPendingDeletion = nil
                Task { await viewModel.deleteMemo(memo) }
            }
            Button("キャンセル", role: .cancel) {
                memoPendingDeletion = nil
            }
        } message: {
            Text("元に戻せません。")
        }
    }

    /// S5 を別ウィンドウで開く。
    ///
    /// `LSUIElement` のアプリは前面に出ないため、**明示的に activate しないと
    /// ウィンドウが他のアプリの後ろに開きます。**
    private func openCanvas(for memo: Memo) {
        viewModel.open(memo)
        openWindow(value: memo.id)
        NSApp.activate()
    }

    // MARK: - 状態表示

    @ViewBuilder
    private var statusBanner: some View {
        let isFailing = viewModel.persistenceStatus == .failing

        HStack(spacing: 8) {
            Image(systemName: isFailing ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(isFailing ? Color.red : Color.orange)

            Text(isFailing ? "保存できません。書き込み先を確認してください" : "保存できていません")
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer(minLength: 4)

            Button("再試行") {
                Task { await viewModel.retryFailedWork() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background((isFailing ? Color.red : Color.orange).opacity(0.14))
    }

    private func hotKeyFailureBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard.badge.exclamationmark")
                .font(.system(size: 11))
                .foregroundStyle(Color.orange)

            Text(message)
                .font(.system(size: 12))
                .lineLimit(2)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.14))
    }

    private var header: some View {
        HStack {
            Text("メモ")
                .font(.system(size: 13, weight: .bold))

            Spacer()

            Button {
                Task { _ = await viewModel.createMemo() }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.didFailToLoad, viewModel.memos.isEmpty {
            // 「0 件」と同じ見た目にしてはいけません。データが消えたと誤解されます。
            loadFailureState
        } else if viewModel.memos.isEmpty {
            emptyState
        } else {
            List {
                Section("雛形") {
                    ForEach(viewModel.memos) { memo in
                        memoRow(memo)
                    }
                }

                // **出ていなければ節ごと隠します。** 空の見出しだけが残ると、
                // 何かを失ったように見えます。
                if !viewModel.presentableStickyNotes.isEmpty {
                    Section("机の上の付箋") {
                        ForEach(viewModel.presentableStickyNotes) { note in
                            stickyNoteRow(note)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    /// 出ている付箋 1 件。
    ///
    /// **雛形とは別に並べます。** 同じ雛形から何枚でも出せるので、
    /// 雛形の行では表せません（[#29](https://github.com/Greatnishioka/qool/issues/29)）。
    private func stickyNoteRow(_ note: StickyNote) -> some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 13, weight: .medium))

                Text(templateTitle(of: note))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                floatingMemos.removeStickyNote(note.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("はがす")
            .frame(width: 22)
        }
    }

    private func templateTitle(of note: StickyNote) -> String {
        viewModel.memos.first { $0.id == note.templateID }?.title ?? "雛形がありません"
    }

    private func memoRow(_ memo: Memo) -> some View {
        HStack(spacing: 4) {
            Button {
                openCanvas(for: memo)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(memo.title)
                            .font(.system(size: 13, weight: .medium))

                        // メインのメモは呼び出しキーごと見せます。覚えていなくても押せます。
                        if hotKeys.isMain(memo) {
                            Text(hotKeys.configuration.prefix.displayName + " F")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    Text("\(memo.canvas.elements.count) オブジェクト")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("メインのメモにする") {
                    hotKeys.setMain(memo)
                }
                .disabled(hotKeys.isMain(memo))

                Button("付箋を出す") {
                    floatingMemos.createStickyNote(from: memo)
                }
                .disabled(!floatingMemos.canCreateStickyNote(from: memo))

                Divider()

                Button("削除", role: .destructive) {
                    memoPendingDeletion = memo
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
        }
    }

    private var footer: some View {
        HStack {
            Button("設定") {
                openWindow(id: SettingsView.windowID)
                NSApp.activate()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Spacer()

            Button("qool を終了") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("メモがありません")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("＋ で新しいメモを作成")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadFailureState: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("メモを読み込めませんでした")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("保存先にアクセスできません")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Button("再読み込み") {
                viewModel.reload()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
