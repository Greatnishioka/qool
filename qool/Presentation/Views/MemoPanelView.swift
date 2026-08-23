import SwiftUI

/// メモパネル。メニューバーから開く、アプリの中心となる画面。
struct MemoPanelView: View {
    @ObservedObject var viewModel: AppRootViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if viewModel.memos.isEmpty {
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
        .frame(width: 320, height: 420)
    }

    private var header: some View {
        HStack {
            Text("メモ")
                .font(.system(size: 13, weight: .bold))

            Spacer()

            Button {
                _ = viewModel.createMemo()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("メモがありません")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
