# qool 機能ドキュメント

このディレクトリは **画面 (ページ) 単位** で、qool の**現在の実装**の機能・仕様・制約をまとめたものです。

> **前提**: ここに書かれているのは現時点で動いているものであり、完成形ではありません。
> qool が目指しているものは [../product/mvp.md](../product/mvp.md) を参照してください。
> 現在の実装は **iOS / iPadOS アプリ**ですが、MVP は Mac 上で動くことを前提としており、
> **macOS アプリとして作り直す方針**です。UI・パラメータは作り直す対象として扱ってください。

## 画面一覧

| # | 画面 | 実装ファイル | ドキュメント |
|---|------|--------------|--------------|
| 1 | メモ一覧 | `Presentation/Views/MemoListView.swift` | [01-memo-list.md](01-memo-list.md) |
| 2 | キャンバス | `Presentation/Views/CanvasView.swift` | [02-canvas.md](02-canvas.md) |
| 3 | 画像切り抜き | `Presentation/Views/ImageCutoutView.swift` | [03-image-cutout.md](03-image-cutout.md) |
| 4 | 画像調整 | `Presentation/Views/ImageAdjustmentView.swift` | [04-image-adjustment.md](04-image-adjustment.md) |

## 画面遷移

```text
ContentView
  └─ AppRootView (NavigationStack)
       └─ メモ一覧
            ├─[メモをタップ / 新規追加]→ キャンバス
            └─ キャンバス
                 └─[メモに画像を追加]→ 画像切り抜き
                      └─[メモ化]→ 画像調整
                           └─[キャンバスへ追加]→ dismiss でキャンバスへ戻る
```

遷移は 2 系統に分かれています。

- メモ一覧 → キャンバス: `navigationDestination(item: $viewModel.selectedMemo)`
- キャンバス → 画像切り抜き → 画像調整: `navigationDestination(for: ImageWorkflowRoute.self)`（`.cutout` / `.adjustment`）

## 状態管理の全体像

| ViewModel | スコープ | 保持する状態 |
|-----------|----------|--------------|
| `AppRootViewModel` | アプリ全体 (`@StateObject` in `ContentView`) | `memos` / `selectedMemo` / `cutoutDraft` / `imageAdjustment` |
| `CanvasViewModel` | キャンバス画面ごと (`@StateObject` in `CanvasView`) | 編集中の `memo` / 選択ツール / 選択中要素 ID / Union 編集状態 / ドラフト要素 |

`CanvasViewModel` は編集のたびに `onSave` クロージャ経由で `AppRootViewModel.saveMemo(_:)` を呼び、
`SaveMemoUseCase` が `updatedAt` を更新してリポジトリへ保存します（明示的な保存ボタンはなく自動保存）。

## 永続化について

現状のリポジトリ実装は [`InMemoryMemoRepository`](../../Infrastructure/Persistence/InMemoryMemoRepository.swift) のみです。

- アプリを再起動すると編集内容はすべて失われます
- 起動時に固定のシードメモ 2 件（「買い物メモ」「切り抜きサンプル」）が入ります
- `MemoRepository.delete(id:)` は定義済みですが、UI からは呼ばれていません

## 関連ドキュメント

- [../spec.md](../spec.md) — もとの画面仕様メモ
- [../architecture/mvvm-clean-architecture.md](../architecture/mvvm-clean-architecture.md) — レイヤ構成と依存方向
- [../image-editing/](../image-editing/README.md) — 別プロジェクト StarWindow で先行開発中の画像編集機能と、取り込み計画
