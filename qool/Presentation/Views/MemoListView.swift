import SwiftUI

struct MemoListView: View {
    @ObservedObject var viewModel: AppRootViewModel

    var body: some View {
        List {
            Section {
                ForEach(viewModel.memos) { memo in
                    Button {
                        viewModel.open(memo)
                    } label: {
                        MemoRowView(memo: memo)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("メモ一覧")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    _ = viewModel.createMemo()
                } label: {
                    Label("新規追加", systemImage: "plus")
                }
            }
        }
    }
}
