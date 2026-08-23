# 4. 画像調整

切り抜いた画像の見え方を整えて、キャンバスに貼り付ける画面です。
[画像切り抜き](03-image-cutout.md)と同じく、現状は**フロー確認用のモック**です。

- View: [`ImageAdjustmentView`](../../Presentation/Views/ImageAdjustmentView.swift)
- スライダー: [`AdjustmentSlider`](../../Presentation/Views/Components/AdjustmentSlider.swift)
- モデル: `ImageAdjustment`（[ImageMemoWorkflow.swift](../../Domain/Models/ImageMemoWorkflow.swift)）

## 画面構成

```text
┌──────────────────────────────┐
│ ‹         画像調整             │
├──────────────────────────────┤
│  ┌────────────────────────┐  │ ← 切り抜きプレビューに調整値をリアルタイム適用
│  │    ╭ ─ ─ ─ ─ ╮         │  │
│  │    │  [photo] │         │  │
│  │    ╰ ─ ─ ─ ─ ╯         │  │
│  └────────────────────────┘  │
│  透明度  ───●────      0.80   │
│  明度    ────●───      0.00   │
│  余白    ──●─────     12.00   │
│  ぼかし  ●───────      0.00   │
│                              │
│  [    ✓ キャンバスへ追加    ]  │
└──────────────────────────────┘
```

## 調整項目

`ImageAdjustment` の 4 パラメータを `Slider` で操作します。値は小数第 2 位まで数値表示されます。

| 項目 | プロパティ | 範囲 | 既定値 | プレビューへの適用 |
|------|-----------|------|--------|--------------------|
| 透明度 | `opacity` | 0.2 〜 1.0 | 0.8 | `.opacity()` |
| 明度 | `brightness` | -0.3 〜 0.3 | 0 | `.brightness()` |
| 余白 | `padding` | 0 〜 36 | 12 | `.padding()` |
| ぼかし | `blur` | 0 〜 8 | 0 | `.blur(radius:)` |

プレビューには `CutoutPreview` を再利用し、`AppRootViewModel.cutoutDraft.pathPoints`
（前画面で転記された頂点列）を表示します。

## キャンバスへ追加

「キャンバスへ追加」で以下が順に実行されます。

1. `updateAdjustment(adjustment)` — 調整値を `AppRootViewModel.imageAdjustment` に保存
2. `commitImageMemo()`
   - `addElement(using: .image)` で `.imageCutout` 要素を生成し `selectedMemo.canvas.elements` に追加
     - 位置・サイズは固定（中心 `(160, 160)`、200×160、塗りはコーラル）
     - 見た目は `CutoutShape`（5 角形の固定シルエット）
   - `cutoutDraft` と `imageAdjustment` を初期値へリセット
3. `dismiss()` でキャンバス画面へ戻る

## 既知の問題

### 調整値が要素に反映されない

`ImageAdjustment` は `AppRootViewModel` に保持されるだけで、
生成される `CanvasElement` には一切引き継がれません（`CanvasElement` 側に対応するプロパティがない）。
さらに `commitImageMemo()` の最後で `.default` にリセットされるため、値は事実上破棄されます。

### 追加した画像が開いているキャンバスに出てこない

`commitImageMemo()` が更新するのは `AppRootViewModel.selectedMemo` ですが、
表示中のキャンバスは `CanvasView` が `@StateObject` として保持する `CanvasViewModel` の
**`memo` のコピー**を描画しています。`@StateObject` は View の生存中に再初期化されないため、
戻ってきたキャンバスには追加した画像要素が現れません。

加えて、その後キャンバス側で編集して `save()` が走ると、画像要素を持たない側の `memo` で
上書き保存されてしまいます。

対処としては、`CanvasViewModel` 側に要素追加の口を用意して
（未使用の `CanvasViewModel.addElement(using:at:)` がそのまま使えます）
画像ワークフローの結果をそちらへ流すか、`CanvasView` が `rootViewModel.selectedMemo` の
変更を購読して ViewModel に同期する形が必要です。

## 本実装で必要になるもの

> 本実装の中身は別プロジェクト **StarWindow** で先行開発されています。
> 表示範囲の編集、ブラシ・投げ縄・色域選択、白フチ除去、テキスト表示域などの仕様は
> [../image-editing/03-adjustment-editor.md](../image-editing/03-adjustment-editor.md)、
> 取り込み時のパラメータ差分は
> [../image-editing/04-integration-plan.md](../image-editing/04-integration-plan.md) を参照してください。

- 調整パラメータを `CanvasElement`（または画像用の新しい要素種別）に保存する
- 実画像に対する調整の適用（Core Image / `CIFilter` などを `Infrastructure` に配置）
- 貼り付け位置・サイズをユーザーが決められるようにする
