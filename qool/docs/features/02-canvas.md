# 2. キャンバス

メモの本体。矩形・パス・直線・テキストを配置し、色や枠線を設定し、図形同士を結合 (Union) できる編集画面です。

- View: [`CanvasView`](../../Presentation/Views/CanvasView.swift)
- 描画・ジェスチャ: [`CanvasSurface`](../../Presentation/Views/Components/CanvasSurface.swift)
- プロパティ: [`CanvasPropertiesPanel`](../../Presentation/Views/Components/CanvasPropertiesPanel.swift)
- ツールバー: [`CanvasToolDock`](../../Presentation/Views/Components/CanvasToolDock.swift)
- ViewModel: [`CanvasViewModel`](../../Presentation/ViewModels/CanvasViewModel.swift)

## レイアウト

```text
┌────────────────────────────────────────────────┐
│ ‹ メモ一覧   買い物メモ      [メモに画像を追加]  │
├────────────────────────────────┬───────────────┤
│                                │ プロパティ     │
│        キャンバス               │  種別 / 座標   │
│      （白 + 24pt グリッド）      │  角丸          │
│                                │  塗り / 枠線   │
│                                │  分割 / 削除   │
│        ┌──────────────────┐    │               │
│        │ ⬚ ✎ ／ T ↖ ドック │    │               │
│        └──────────────────┘    │               │
└────────────────────────────────┴───────────────┘
```

- **プロパティパネルは幅 820pt 以上のときだけ表示されます**（`proxy.size.width >= 820`）。
  iPhone 縦持ちなど狭い画面ではパネルが出ないため、色・枠線・角丸・削除などの編集操作ができません。
- ツールドックは画面下部固定。`GlassEffectContainer` + `glassEffect` による Liquid Glass 表現で、
  選択中ツールのハイライトは `matchedGeometryEffect` でアニメーションします。

## ツール

`CanvasTool` は 6 種類定義されていますが、**ドックに並ぶのは 5 種類**です（`.image` は
ナビゲーションバーの「メモに画像を追加」から入る[画像切り抜きフロー](03-image-cutout.md)専用）。

| ツール | アイコン | 操作 | 生成される要素 |
|--------|----------|------|----------------|
| 選択 | `cursorarrow` | タップ / ドラッグで選択・移動 | — |
| 矩形 | `rectangle` | ドラッグした範囲 | `.rectangle`（塗り: 紙） |
| パス | `point.topleft.down.curvedto.point.bottomright.up` | タップで頂点を打つ | `.path`（塗り: スカイ） |
| 直線 | `line.diagonal` | ドラッグした始点→終点 | `.line`（太さ 4、角度は `rotationAngleDegrees` に保存） |
| テキスト | `textformat` | ドラッグした範囲 | `.text`（初期文字列「テキスト」） |
| (画像) | `photo` | ドック非表示 | `.imageCutout` |

ツールを切り替えると (`selectTool`)、選択ツール以外では選択状態がクリアされます。
パスツールから他ツールへ移ると、打ちかけの頂点は破棄されます。

## 描画

### ドラッグで描く（矩形 / 直線 / テキスト / 画像）

[`CanvasDraftElementBuilder`](../../Domain/Services/CanvasDraftElementBuilder.swift) が担当します。

1. ドラッグ中は `updateDraft` がドラフト要素を作り、キャンバス上に不透明度 0.72 で仮表示
2. 始点・現在地はキャンバス矩形内にクランプされる
3. 指を離すと `commitDraft`。`isDrawable` を満たす場合のみ確定
   - 直線: 幅 8pt 以上
   - それ以外: 幅・高さともに 8pt 以上
4. 確定後は **自動的に選択ツールへ戻り**、追加した要素が選択状態になる

直線は始点・終点から長さと角度 (`atan2`) を求め、`frame` は「長さ × 28pt」の水平矩形を
`rotationAngleDegrees` で回転させる形で表現されます。

### タップで描く（パス）

`placePathPoint` がタップ位置を頂点として追加していきます。

- 頂点を打つたびに **開いたパス**としてプレビュー（塗り 0.18、頂点にマーカー表示。始点だけアクセントカラー）
- **頂点が 3 つ以上あるとき、始点から 18pt 以内をタップするとパスを閉じて確定**
- 確定時に頂点が 3 未満ならキャンセル
- 描画はベジェ平滑化（隣接点の中点を通る二次曲線）されるため、カクカクせず曲線になります

頂点は要素の `frame` に対する正規化座標 (`NormalizedPoint`, 0〜1) で保持されます。

## 選択

[`CanvasSelectionService`](../../Domain/Services/CanvasSelectionService.swift) が判定を担当し、
選択は `Set<CanvasElement.ID>` で管理されるため複数選択に対応しています。

| 操作 | 挙動 |
|------|------|
| 要素をタップ | 単一選択（既存の選択は置き換え） |
| **Shift + タップ** | 選択のトグル（追加 / 解除） |
| 何もない場所からドラッグ | マーキー矩形選択。矩形と**交差**する要素をすべて選択（4pt 未満のドラッグは選択解除扱い） |
| 何もない場所をタップ | 選択解除 |
| 選択中の要素をドラッグ | 選択中の要素すべてを移動 |
| 結合要素をダブルタップ | [Union 編集モード](#union-結合)へ |

### ヒット判定

`hitFrame(for:)` が要素の `frame` を広げた矩形で判定します。細くて掴みづらい直線だけ広め。

- 直線: 16pt 拡張
- それ以外: 4pt 拡張

要素は描画順の**逆順**に探索されるため、後から置いた（＝手前の）要素が優先されます。

### Shift キーの検出

外部キーボード / iPad の Magic Keyboard 前提の実装です。2 経路で取得しています。

- `UIResponder.pressesBegan/Changed/Ended` の `modifierFlags`（`ModifierKeyReader` という `UIViewRepresentable`）
- `GameController` の `GCKeyboard.coalesced` から左右 Shift の押下状態

### ダブルタップ検出

SwiftUI の標準ジェスチャではなく、`registerTap(at:)` が自前で判定しています
（**前回タップから 0.35 秒以内、かつ 24pt 以内**なら 2 回目とみなす）。
既存のドラッグジェスチャと共存させるための実装です。

## 移動

`moveSelectedElement` → [`CanvasEditingUseCases.moveElements`](../../Application/UseCases/CanvasEditingUseCases.swift)。

- 選択中の要素をまとめて平行移動
- **選択範囲全体の外接矩形がキャンバス外に出ないようにクランプ**（個々の要素ではなくグループ単位）
- 結合要素を動かした場合は、内部に持つ構成元スナップショットの座標も同じ量だけ追従させます

## プロパティ編集

### 単一選択時

| 項目 | 対象 | 内容 |
|------|------|------|
| 種別 / 座標 | 全要素 | 「矩形 / パス / 直線 / テキスト / 画像」と `x`,`y` を表示（読み取り専用） |
| テキスト | `.text` | `TextField` で本文を編集 |
| 角丸 | `.rectangle` | スライダー。上限は `min(width, height) / 2` に自動でクランプ |
| 塗り | 全要素 | スウォッチをタップして popover の `ColorPicker`。HEX + 不透明度 % を表示 |
| 枠線 | 全要素 | ON/OFF トグル。ON 時のみ色と太さ (0〜12) を表示。太さ 0 にすると自動的に OFF |
| 分割 | 結合要素のみ | [Union の解除](#分割-separate) |
| 削除 | 全要素 | 選択中の要素を削除 |

色は `CanvasColor` 列挙型。プリセット（紙 / ミント / コーラル / スカイ / インク / 透明）に加え、
`ColorPicker` からの選択は `.custom(red:green:blue:opacity:)` として保存されます。

### 複数選択時

- 「N 個のオブジェクト」「複数選択中」の表示
- **結合**ボタン（2 つ以上選択時に有効）
- **まとめて削除**ボタン

## Union (結合)

[`CanvasUnionUseCase`](../../Application/UseCases/CanvasUnionUseCase.swift) が
外部ライブラリ **[iOverlay](https://github.com/iShape-Swift/iOverlay)** を使ってブーリアン和を計算します。

### 対象と非対象

| 種別 | 結合可否 |
|------|----------|
| 矩形 | ○ |
| パス | ○（**閉じたパスのみ**） |
| 直線 / テキスト / 画像 | × （無視される） |

結合可能な要素が 2 つ未満の場合は何も起きません。

### 処理の流れ

1. 各要素をポリゴンの頂点列に変換
   - 矩形: 4 頂点。角丸がある場合は円弧を 6〜16 分割してサンプリング
   - パス: 描画と同じ二次ベジェを距離に応じて 10〜32 分割してサンプリング（見た目と結合結果を一致させるため）
2. 1 つ目を `subject`、残りを `clip` として `CGOverlay` に投入
3. `fillRule: .nonZero` / `overlayRule: .union` で shape を抽出
4. 結果を `.path` 要素として再構築
   - 穴あき形状に対応するため複数の輪郭を `pathContours` に持ち、描画は `eoFill`（偶奇則）
   - 塗り・枠線などのスタイルは 1 つ目の要素から引き継ぎ
   - **結合前の要素を `unionSourceElements` にスナップショットとして保存**

### 結合後の編集（Union 編集モード）

結合要素をダブルタップすると `editingUnionElementID` がセットされ、構成元が半透明で重ねて表示されます
（選択中の構成元は 0.62、それ以外は 0.34）。

- 構成元をドラッグすると位置が変わり、**その場で Union を再計算**して結合結果を差し替えます
- 構成元が矩形なら、プロパティパネルの「構成元の角丸」スライダーで角丸を変えて再計算できます
- 再計算時も要素 ID とスタイルは維持されるため、選択状態が途切れません

### 分割 (Separate)

プロパティパネルの「分割」で `separateSelectedElement()` を実行し、
結合要素を削除して `unionSourceElements` から元の要素群を復元します。復元後は全部が選択状態になります。

## 保存

保存ボタンはありません。要素の追加・移動・編集・削除のたびに `CanvasViewModel.save()` が走り、
`AppRootViewModel.saveMemo(_:)` → `SaveMemoUseCase`（`updatedAt` を現在時刻に更新）→ リポジトリ、の順で反映されます。

## 現時点の制約 / 未実装

- **リサイズができない**。選択枠 (`SelectionOutline`) の四隅のハンドルは装飾のみで、ドラッグに反応しません
- **回転 UI がない**。`rotationAngleDegrees` は直線を描くときに内部利用されるだけです
- **Undo / Redo がない**
- **重なり順 (z-order) の変更ができない**。配列の末尾が常に手前
- 画面幅 820pt 未満ではプロパティパネルが出ないため編集操作が制限されます
- キーボードの Delete キーなどのショートカット未対応（削除はパネルのボタンのみ）
- `CanvasViewModel.addElement(using:at:)` は現在どの View からも呼ばれていません（ドラッグ描画に置き換わったため）
- [spec.md](../spec.md) にある「パスを用いて入力欄を設定できる」は未実装です
- 画像調整から追加した画像は、開いたままのキャンバスにはすぐ反映されません（[画像調整の注意](04-image-adjustment.md#既知の問題)を参照）
