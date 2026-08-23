# 3. メモ調整画面（表示範囲エディタ）

`MemoCreationPreviewSheet`（860×640 のシート、約 1,200 行）が担当する部分で、
qool の[画像調整画面](../features/04-image-adjustment.md)に相当します。
qool 側の現状（スライダー 4 本）に対し、**ここが機能量としては最大の差分**です。

## レイアウト

```text
┌──────────────────────────────────────────────────────────┐
│ メモの調整                            [キャンセル][作成]   │
├──────────────────────────────┬───────────────────────────┤
│                              │ ▼ 表示                     │
│                              │   薄さ / 明度 / 余白        │
│      プレビュー               │ ▼ 輪郭                     │
│   （ピンチズーム・パン可）      │   ぼかし / ぼかし方向        │
│                              │   [表示範囲修正]            │
│   輪郭 = 点線                 │   編集ツール(5種)           │
│   選択範囲 = シアン            │   投げ縄解除 / 色域許容誤差  │
│   テキスト域 = オレンジ         │   パスをスムース化 / 白フチ除去│
│   詳細抽出 = 紫               │   直線 / 曲線 / ブラシ       │
│                              │   部分詳細抽出              │
│                              │   輪郭リセット / 下書きクリア  │
│                              │ ▼ テキスト表示域            │
│                              │   [テキスト範囲指定]         │
└──────────────────────────────┴───────────────────────────┘
```

## プレビュー操作

| 操作 | 挙動 |
|------|------|
| ピンチ | ズーム（0.45〜4 倍） |
| 二本指スクロール | パン |
| **スペースキー + ドラッグ** | パン |
| ホバー | ペン／消しゴム時にブラシサイズの円を表示 |

パンは SwiftUI のジェスチャでは扱えないため、`PreviewPanInputView`（`NSViewRepresentable`）が
`NSEvent.addLocalMonitorForEvents` で `.scrollWheel` / `.keyDown` / `.keyUp` / `.leftMouseDragged` を
横取りして実現しています（スペースのキーコードは 49）。

表示範囲編集中は、切り抜き範囲の**外側の元画像も 10% の不透明度で表示**されるため、
「今どこを削っているか」が画像全体の中で分かるようになっています。

## 「表示」グループ

| 項目 | プロパティ | 範囲 | 既定 |
|------|-----------|------|------|
| 薄さ | `paperOpacity` | 0.2 〜 1.0 | 0.2 |
| 明度 | `paperBrightness` | -0.15 〜 0.45 | 0.1 |
| 余白 | `contourPaddingPixels` | 0 〜 80 px | 60 |

`CutoutImageRenderer.renderCrop` が `bounds` で切り出しつつ、
`opacity` を `draw(fraction:)` に、`brightness` を白／黒の半透明オーバーレイ（最大 0.45）として適用します。

## 「輪郭」グループ

### ぼかし

- `contourBlurRadius` 0 〜 14 px
- `contourBlurMode`: 外側 / 内側 / 両側

`ContourMaskView` がマスク形状に `.blur()` をかけます。
**注意: 現在の実装では `.outside` と `.both` の処理が同一**（どちらも `shape.blur(radius:)`）で、
`.inside` だけが `.blur().mask(shape)` として区別されています。実質 2 種類しか効きません。

### 表示範囲修正モード

「表示範囲修正」を押すと `isDisplayRangeEditing = true` になり、
現在の輪郭から **1024×1024 のラスターマスク** (`RasterContourMask`) を生成します。

> 表示範囲修正中はラスターマスクだけを編集します。保存時に輪郭パスへ変換します。

というのが基本方針で、「表示範囲を保存」で `RasterContourMask.contourPoints()`
（境界追跡 → 最大面積のループを採用 → 簡略化）がパス化し、`configuration.editedContour` に入ります。

ベクタのパスを直接編集するのではなくラスターを経由することで、
ペンで描き足す／消しゴムで削るといった**位相が変わる編集**（穴を開ける、分離する）を素直に扱えます。

### 編集ツール（5 種）

`MemoPreviewTool` の 5 つ。表示範囲修正中でないと選べません。

| ツール | 内容 |
|--------|------|
| 確認 `move` | 編集せず、ズーム／パンだけ |
| 投げ縄 `lasso` | 囲んだ範囲を選択範囲として保存。**以降の操作はすべてこの範囲内に限定される** |
| 色域選択 `colorRange` | クリックした色に近いピクセルを選択。許容誤差スライダー (0.01〜0.45) でリアルタイム再計算。投げ縄選択がある場合はその中だけが対象 |
| 輪郭ペン `pencil` | ラスターマスクに描き足す |
| 輪郭消しゴム `eraser` | ラスターマスクから削る |

投げ縄／色域選択で作った `RasterSelectionMask` は、ペン・消しゴム・スムース化・白フチ除去の
**すべての操作に対するマスク**として働きます。「この部分だけ直したい」を実現する仕組みです。

### ブラシの描き方（3 モード）

ペン／消しゴム時に切り替えられます。

| モード | 操作 |
|--------|------|
| 通常 | ドラッグ中に円を連続で塗る。**プレビュー画像の更新はドラッグ終了時にまとめて行う**（ドラッグ中の再描画が重いため） |
| 直線 | 始点→終点を指定し、離すと直線を塗る／消す |
| 曲線 | クリックで制御点を置き、Catmull-Rom スプラインで補間。「曲線滑らかさ」(0〜1) で直線⇔曲線を線形ブレンド。「曲線を適用」で確定、「1点戻す」「曲線クリア」あり |

ブラシサイズは `brushSizePixels` 1〜80 px。ただしこれは
**基準解像度 640 (`contourEditingReferenceResolution`) 上のピクセル数**で、
実際のマスク解像度 1024 へは `scaledMaskPixels()` で換算されます。

### パスをスムース化

現在の編集輪郭に対して `ContourSmoother.smoothForEditing` を実行します（[詳細](02-contour-extractors.md#スムース化パイプライン)）。
選択範囲があればその区間だけが対象です。実行結果は `smoothedEditingContour` としてベクタで保持され、
以降のラスター編集が入ると `ensureRasterMaskForRasterEditing()` が再ラスタライズします。

### 白フチ除去

被写体マスク由来の切り抜きで縁に残る白い縁取りを消すための機能です。

1. ラスターマスクを `displayRangeWhiteFringeInsetPixels` = 2px 相当だけ内側へ収縮 (`erode`)
2. 輪郭を取り直す
3. スムース化して表示

選択範囲があればその周辺だけを処理します。

### 部分詳細抽出

複雑な縁（髪の毛、切り込みなど）だけを囲んで再抽出する機能です。

1. 「部分詳細抽出」でモードに入り、プレビュー上をクリックして ROI を囲む（紫の点線）
2. **始点付近（0.025 以内）をクリックすると確定**
3. `RasterContourMask.refineRegion(image:roi:keepInteriorFilled:)` が実行される
   - ROI の境界付近から背景色を推定
   - 背景色に近いピクセルを外部背景として flood fill
   - ROI 内で外部背景とつながる領域をマスクから削る

## 「テキスト表示域」グループ

本文を配置する範囲をパスで指定する機能です。**qool の [spec.md](../spec.md) にある
「パスを用いて入力欄を設定できる」がこれに相当します。**

- 「テキスト範囲指定」でモードに入り、プレビュー上をクリックして点を置く（オレンジ）
- 点は直線で結ばれる。「1点戻す」「下書きクリア」あり
- **3 点以上のとき始点付近（0.025 以内）をクリックすると確定**し、`ContourSmoother.polished()` を通して `configuration.textPath` に保存
- 「テキスト範囲リセット」で解除

指定した領域は最終出力で `ShapedTextEditor` に渡され、
`TextExclusionPathBuilder` が **フォントサイズの 0.45 倍ごとの水平バンドで多角形との交差を計算**し、
`NSTextView.textContainer.exclusionPaths` として設定します。
これにより、本文が任意形状の内側だけに流し込まれます。

## リセット

| ボタン | 内容 |
|--------|------|
| 輪郭リセット | `editedContour` / ラスターマスク / 選択範囲 / 各種下書きをすべて破棄し、編集モードを抜ける |
| 下書きクリア | 確定前の下書き（直線・曲線・投げ縄・詳細抽出のパス）だけを消す |

## 出力（macOS 固有）

「作成」で `MemoPreviewConfiguration` が確定し、`openCutoutWindow` が呼ばれます。

1. マスク輪郭を決める（`editedContour` があればそれ、なければ `ContourPadding.expanded` した基準輪郭）
2. `CutoutImageRenderer.renderCrop` で bounds を切り出し、薄さ・明度を適用
3. `CutoutWindowManager.shared.openWindow` が **borderless / 透明 / floating の `NSWindow`** を開く
   - 幅 360pt 固定、高さは画像のアスペクト比（0.4〜2.5 にクランプ）
   - `CutoutHostingView.hitTest` が輪郭多角形の内側でしかイベントを受けない
     → **輪郭の外側はクリックが背面のアプリに抜ける**
   - `textPath` があると、テキスト編集はさらにその内側でしか反応しない
   - 開くたびに 24pt ずつずらして配置（最大 5 段）

**この出力部分は qool には移植しません。** qool ではキャンバス上の要素として貼り付けます。

## 設定オブジェクト

調整画面から出力へ渡るのは `MemoPreviewConfiguration` だけです。

```swift
struct MemoPreviewConfiguration {
    var paperOpacity          // 薄さ
    var paperBrightness       // 明度
    var contourPaddingPixels  // 余白
    var contourBlurRadius     // 輪郭ぼかし
    var contourBlurMode       // ぼかし方向
    var editedContour: [CGPoint]?   // 編集後の輪郭（未編集なら nil）
    var textPath: [CGPoint]?        // テキスト表示域（未指定なら nil）
    var brushSizePixels
}
```
