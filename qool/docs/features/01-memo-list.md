# 1. メモ一覧

作成済みメモを一覧し、既存メモを開く／新規メモを作るための起点となる画面です。

- View: [`MemoListView`](../../Presentation/Views/MemoListView.swift)
- 行コンポーネント: [`MemoRowView`](../../Presentation/Views/Components/MemoRowView.swift)
- ViewModel: [`AppRootViewModel`](../../Presentation/ViewModels/AppRootViewModel.swift)
- UseCase: `LoadMemosUseCase` / `CreateMemoUseCase`（[MemoUseCases.swift](../../Application/UseCases/MemoUseCases.swift)）

## 画面構成

```text
┌──────────────────────────────┐
│ メモ一覧                  [+] │  ← ナビゲーションバー右に「新規追加」
├──────────────────────────────┤
│ [icon] 買い物メモ              │
│        2 オブジェクト       ›  │
├──────────────────────────────┤
│ [icon] 切り抜きサンプル         │
│        1 オブジェクト       ›  │
└──────────────────────────────┘
```

## 機能

### メモの一覧表示

`AppRootViewModel.reload()` が `LoadMemosUseCase` を実行して `memos` を更新します。
並び順はリポジトリ側で **`updatedAt` の降順**（最近更新したメモが先頭）に固定されています。

1 行あたりの表示内容は `MemoRowView` が担当します。

| 要素 | 内容 |
|------|------|
| サムネイル | 44×44 の角丸矩形 + `note.text` の SF Symbol（**メモ内容のプレビューではなく固定アイコン**） |
| タイトル | `memo.title` |
| サブテキスト | `"\(memo.canvas.elements.count) オブジェクト"` |
| アクセサリ | `chevron.right` |

### メモを開く

行タップで `AppRootViewModel.open(_:)` が `selectedMemo` に代入し、
`navigationDestination(item:)` によって [キャンバス画面](02-canvas.md) へ push されます。

### 新規メモの作成

ナビゲーションバー右上の「新規追加」（`plus`）で `AppRootViewModel.createMemo()` を実行します。

1. `CreateMemoUseCase` が **タイトル固定「新規メモ」** ・空キャンバスの `Memo` を生成して保存
2. `reload()` で一覧を更新
3. `selectedMemo` に代入され、そのままキャンバス画面へ遷移

## 現時点の制約 / 未実装

- **タイトルの編集・入力ができない**。新規メモは常に「新規メモ」という名前になります
- **削除 UI がない**。`MemoRepository.delete(id:)` は定義済みですが呼び出し元がありません（スワイプ削除・編集モードとも未実装）
- 検索・並べ替え・フォルダ分けなし
- サムネイルがキャンバス内容を反映しない
- `InMemoryMemoRepository` のため、アプリ終了で内容は消えます
