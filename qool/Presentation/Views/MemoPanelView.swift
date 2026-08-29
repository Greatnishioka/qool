import SwiftUI

/// メモパネル。メニューバーから開く、アプリの中心となる画面。
struct MemoPanelView: View {
    @ObservedObject var viewModel: AppRootViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 失敗しているときだけ出る。常時は何も足しません。
            if viewModel.persistenceStatus != .ok {
                statusBanner
                Divider()
            }

            header

            Divider()

            content
        }
        .frame(width: 320, height: 420)
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
            List(viewModel.memos) { memo in
                VStack(alignment: .leading, spacing: 2) {
                    Text(memo.title)
                        .font(.system(size: 13, weight: .medium))
                    Text("\(memo.canvas.elements.count) オブジェクト")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
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
