# 3. 画像切り抜き

画像をパスで囲んで、メモに貼る範囲を決める画面です。旧プロジェクトから移植予定の機能で、
**現状の実装はフロー確認用のモック**です。

- View: [`ImageCutoutView`](../../qool/Presentation/Views/ImageCutoutView.swift)
- プレビュー: [`CutoutPreview`](../../qool/Presentation/Views/Components/CutoutPreview.swift)
- モデル: `ImageCutoutDraft` / `NormalizedPoint`（[ImageCutoutDraft.swift](../../qool/Domain/Models/ImageCutoutDraft.swift) / [NormalizedPoint.swift](../../qool/Domain/Models/NormalizedPoint.swift)）

## 導線

[キャンバス画面](02-canvas.md)のナビゲーションバー右上「メモに画像を追加」
（`ImageWorkflowRoute.cutout`）から遷移します。

## 画面構成

```text
┌──────────────────────────────┐
│ ‹        画像切り抜き          │
├──────────────────────────────┤
│  ┌────────────────────────┐  │
│  │   ╭ ─ ─ ─ ─ ─ ╮        │  │ ← 正方形 (aspectRatio 1) のプレビュー
│  │   │   [photo]  │        │  │   点線パス + 半透明の塗り
│  │   ╰ ─ ─ ─ ─ ─ ╯        │  │
│  └────────────────────────┘  │
│                              │
│  画像切り抜き                  │
│  画像をパスで囲い、メモ化する    │
│  範囲を決めます。               │
│                              │
│  [        ✂ メモ化        ]   │
└──────────────────────────────┘
```

`CutoutPreview` は正規化座標 (0〜1) の頂点列から `Path` を作り、
アクセントカラーの塗り (0.24) と破線ストローク (太さ 3、dash `[8, 5]`) で囲み範囲を表示します。

## 現在の実装

| 項目 | 状態 |
|------|------|
| 画像の選択 | **未実装**。画像を取り込む口がなく、SF Symbol の `photo` を表示するだけ |
| パスの編集 | **未実装**。`@State private var pathPoints` にハードコードされた 4 点の固定形状 |
| `onAppear` | その固定パスを `AppRootViewModel.cutoutDraft.pathPoints` に転記 |
| 「メモ化」 | `ImageWorkflowRoute.adjustment` へ push（[画像調整](04-image-adjustment.md)） |

`ImageCutoutDraft.sourceDescription` は既定値 `"未選択の画像"` のまま、どこからも更新・参照されていません。

## 本実装で必要になるもの

> 本実装の中身は別プロジェクト **StarWindow** で先行開発されています。
> なぞりから輪郭候補の抽出・選択までの仕様は
> [../image-editing/01-cutout-flow.md](../image-editing/01-cutout-flow.md) を参照してください。

[architecture ドキュメント](../architecture/mvvm-clean-architecture.md) の方針どおり、
旧プロジェクトの切り抜きアルゴリズムは `Infrastructure` に置き、`Application/UseCases` から呼び出して
SwiftUI View と画像処理を結合させない構成が想定されています。

- 画像の取り込み（ファイル選択 / ドラッグ&ドロップ / ペースト）
- パスの対話的な編集（頂点の追加・移動・削除、閉じる操作）
- 実際のマスク生成と切り抜き画像の書き出し
- 切り抜き結果を `CanvasElement`（`.imageCutout`）に紐づけて保持する仕組み
  — 現状の `CanvasElement` には画像データを持つプロパティがありません
