import SwiftUI

/// S5 キャンバス編集ウィンドウの入れ物。
///
/// `WindowGroup(for:)` から渡されるのはメモの ID だけなので、ここで一覧から引き当てます。
/// **`Memo` そのものを渡さないのは、ウィンドウの復元情報がディスクに保存されるため**です。
/// 値を丸ごと持たせると、復元時に古い内容で開いてしまいます。
struct CanvasWindowView: View {
    let memoID: Memo.ID?
    @ObservedObject var rootViewModel: AppRootViewModel

    var body: some View {
        if let memoID, let memo = rootViewModel.memos.first(where: { $0.id == memoID }) {
            CanvasView(memo: memo, rootViewModel: rootViewModel)
                .id(memo.id)
        } else {
            ContentUnavailableView(
                "メモが見つかりません",
                systemImage: "questionmark.square.dashed",
                description: Text("削除されたか、まだ読み込まれていません")
            )
        }
    }
}
