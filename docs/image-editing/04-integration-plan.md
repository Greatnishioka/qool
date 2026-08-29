# 4. qool への取り込み計画

StarWindow（macOS / AppKit）の機能を qool（iOS / iPadOS / SwiftUI）へ移すときの
対応関係と、実際に問題になる箇所の整理です。

## 4.1 レイヤ配置

qool の [MVVM + Clean Architecture](../architecture/mvvm-clean-architecture.md) に合わせると、
StarWindow の構成はほぼそのまま対応します（StarWindow 側も同じ構成へ分割済み）。

| qool のレイヤ | 置くもの |
|---------------|----------|
| `Domain/Models` | `ContourCandidate` / `ContourCandidateSource` / `RasterContourMask` / `RasterSelectionMask` / `ContourBlurMode` |
| `Domain/Services` | `ContourSmoother` / `ContourPadding` / `ContourCandidateSelector` / `ContourQualityValidator` / `RectangularGuideContour` / `CurvePathBuilder` |
| `Application/UseCases` | 「輪郭候補を抽出する」「マスクを編集する」「切り抜き画像を書き出す」の 3 系統 |
| `Infrastructure` | Vision / CoreImage の各抽出器、画像レンダラ、画像の読み込みと保存 |
| `Presentation` | 切り抜き画面・調整画面の View と ViewModel |

**移植の難易度は Domain と Infrastructure で大きく違います。**

- `Domain/Services` の 5 つは `CGPoint` と `CGRect` しか使わない純粋ロジックで、**そのまま動きます**
  （ただし全ファイルが機械的に `import AppKit / Vision / SwiftUI` を書いているので、不要な import の除去が必要）
- `Infrastructure` は `NSImage` / `CGContext` / AppKit 前提で、書き換えが要ります

## 4.2 プラットフォーム

**qool は macOS 専用アプリとして作り直すことが決定しています**
（[理由](../product/mvp.md#決定プラットフォーム-macos-専用)）。iOS / iPadOS には対応しません。
StarWindow は最初から macOS / AppKit で書かれているため、**この前提だと移植コストは大きく下がります。**

### そのまま使えるもの

書き換えの必要がなく、設計判断ごと持ってこられる部分です。

| 実装 | 内容 |
|------|------|
| `NSImage` / `CGContext` / `lockFocus` | 画像の読み込み・切り出し・合成 |
| `NSOpenPanel` + ドラッグ&ドロップ | 画像の取り込み |
| `NSTextView.textContainer.exclusionPaths` | 任意形状へのテキスト流し込み |
| `NSBezierPath` | テキスト除外パスの構築 |
| `NSEvent.addLocalMonitorForEvents` | スペース + ドラッグ / スクロールによるパン |
| `onContinuousHover` | ブラシサイズのカーソル表示（**マウスカーソルがある Mac では素直に成立します**） |
| borderless `NSWindow` + 輪郭ヒットテスト | 任意形状のフローティングメモ。**MVP のコア機能そのもの**（下記 4.8） |
| Vision / CoreImage の各抽出器 | 7 種類の輪郭抽出 |

### 逆に書き換えが必要なのは qool 側

移植の向きが逆転します。**AppKit → UIKit ではなく、qool の UIKit 依存を外す**作業になります。

| qool の現状 | 対応 |
|-------------|------|
| `SDKROOT = iphoneos` / `TARGETED_DEVICE_FAMILY = "1,2"` | **macOS 専用プロジェクトとして作り直す**（マルチプラットフォーム化はしない） |
| [`CanvasSurface`](../../qool/Presentation/Views/Components/CanvasSurface.swift) の `import UIKit` / `UIPress` / `GameController` | Shift キー検出は macOS では `NSEvent.modifierFlags` で素直に取れる |
| [`CanvasPropertiesPanel`](../../qool/Presentation/Views/Components/CanvasPropertiesPanel.swift) の `import UIKit`（`UIColor` での色成分取得） | `NSColor` へ置き換え |
| ツールドックの下部固定レイアウト | タッチ前提の設計。Mac ではツールバー / インスペクタ形式へ見直し |
| `Color(.systemGroupedBackground)` などの UIKit セマンティックカラー | AppKit の対応する色へ |

なお `CanvasSurface` の自前ダブルタップ検出（0.35 秒 / 24pt）や、
ドラッグジェスチャ内でヒットテストして選択・移動・マーキーを切り替えるロジックは
プラットフォーム非依存なので、そのまま活かせます。

### Vision / API の可用性

**qool では [モダンな Vision API を使うことが決定しています](../product/mvp.md#決定vision-はモダン-api-を使う)**
（`VN` 接頭辞の旧 API ではなく、macOS 15 以降の Swift ネイティブな `async` ベースのリクエスト型）。

- StarWindow は **旧 API で書かれている**ため、抽出器の Vision 呼び出し部分は**書き換えになります**
- 書き換わるのは呼び出し方だけで、**ロジック（どの結果をどう正規化座標へ変換し、どう候補にするか）は
  そのまま流用できます**。移植で価値があるのはそちらです
- CoreImage ベースの抽出器（背景差分 / 線色 / 色矩形）は Vision を使っていないため影響を受けません
- デプロイメントターゲットは [macOS 26 以上](../product/mvp.md#決定デプロイメントターゲット-macos-26-以上)で確定しています（Vision の要件は 15 以上、Liquid Glass の要件が 26 以上）

## 4.3 qool 側のモデル拡張

現在の `CanvasElement` には**画像を持つ手段がありません**。`.imageCutout` は
固定シルエット (`CutoutShape`) を塗り色で描いているだけです。

必要になるもの:

- 画像本体への参照（`NSImage` を直接持たず、ID でリポジトリ経由が望ましい。`Memo` は `Equatable`/`Hashable` なので画像を値として持たせると比較コストが問題になります）
- 切り抜き輪郭 — **既存の `pathContours: [CanvasPathContour]` がそのまま使えます**（正規化座標という前提も一致）
- 調整パラメータ（不透明度・明度・余白・ぼかし半径・ぼかし方向）
- テキスト表示域パス（`textPath` 相当）

輪郭を `pathContours` で表現できると、
**切り抜き画像が[キャンバスの Union 機能](../features/02-canvas.md#union-結合)の対象にできる**可能性があります
（現在 `CanvasUnionUseCase.isUnionable` は `.imageCutout` を除外していますが、これは形状データがないためです）。

### 調整パラメータ

qool 側の `ImageAdjustment` と StarWindow の `MemoPreviewConfiguration` は項目が近いものの、
範囲と既定値が食い違っています。ただし **qool 側の現行 UI は作り直す前提なので、これは調整すべき差分ではなく、
「StarWindow の値を出発点にして、qool 側を捨てる」で構いません。**

以下は移行時の参照用です。

| 項目 | qool `ImageAdjustment`（捨てる側） | StarWindow `MemoPreviewConfiguration`（採用する側） |
|------|------------------------------------|---------------------------------------------------|
| 透明度 / 薄さ | 0.2 〜 1.0（既定 0.8） | 0.2 〜 1.0（既定 0.2） |
| 明度 | -0.3 〜 0.3（既定 0） | -0.15 〜 0.45（既定 0.1） |
| 余白 | 0 〜 36（既定 12） | 0 〜 80 px（既定 60） |
| ぼかし | 0 〜 8（既定 0） | 0 〜 14 px（既定 0） |
| ぼかし方向 | なし | 外側 / 内側 / 両側 |
| 編集後輪郭 | なし | `editedContour` |
| テキスト表示域 | なし | `textPath` |

qool の `ImageAdjustment` にしかない概念はありません。**StarWindow 側が完全に上位互換**です。

なお現在の qool は調整値を `CanvasElement` に引き継がず破棄しています
（[既知の問題](../features/04-image-adjustment.md#既知の問題)）。作り直しの際に自然に解消される想定です。

## 4.4 永続化

> 方式の比較と推奨案は [architecture/persistence.md](../architecture/persistence.md) にまとめています。

qool のリポジトリは [`InMemoryMemoRepository`](../../qool/Infrastructure/Persistence/InMemoryMemoRepository.swift) のみで、
アプリを閉じると消えます。画像を扱うようになると:

- 元画像 / 切り抜き結果 / マスクをファイルとして保存する仕組みが要る
- `Memo` の値型に画像を含めない設計（ID 参照 + 画像リポジトリ）にしないと、
  `@Published var memo` の更新のたびに巨大な値のコピーと `Equatable` 比較が走る

## 4.5 UI

StarWindow の調整画面は **860×640 のシート + 幅 300pt の固定サイドパネル**です。
Mac のウィンドウとしては素直な構成で、**そのまま出発点にできます。**
タッチ前提だったときに問題になっていた事項（hover が使えない、指がブラシを隠す、パンと描画の衝突）は
すべて解消されます。

残る課題は情報量の整理です。

| 課題 | 内容 |
|------|------|
| ボタン・トグル・スライダーが多い | 調整画面だけで 15 個以上。ツールごとに出し分ける整理が要る |
| モードの階層が深い | 「表示範囲修正中」かつ「ペン」かつ「曲線」といった状態の掛け算があり、無効化されたコントロールが並ぶ |
| ぼかし方向の実装漏れ | `.outside` と `.both` が同一処理（[詳細](03-adjustment-editor.md#ぼかし)）。UI として 3 択に見えているが実質 2 択 |

逆に、qool 側のキャンバス画面は**タッチ前提で作られているため Mac 向けに見直しが必要**です。

- 下部固定のツールドック → ツールバー / インスペクタ形式へ
- 「幅 820pt 未満ではプロパティパネルを出さない」という割り切りは、Mac では不要
- Shift + クリックの複数選択、マーキー選択、ダブルクリックでの Union 編集は
  **もともと Mac の操作体系に近い**ので、そのまま活きます

## 4.6 パフォーマンス

StarWindow は macOS のデスクトップ性能を前提に、重い処理をメインスレッドで同期実行しています。
**Mac 上で動かす限りは前提が変わらないため、モバイルへ持っていく場合ほどの危険はありません。**
ただし「実用に耐えるか」は別問題で、以下は体感速度に直結します。

| 処理 | 負荷 |
|------|------|
| ラスターマスク | 1024×1024（`contourEditingRasterResolution`）の `[UInt8]` を保持。全面走査が多数 |
| 色域選択 | 1,048,576 ピクセルすべてに対して色サンプリングと距離計算。**許容誤差スライダーを動かすたびに再実行** |
| 輪郭候補抽出 | 7 種類の抽出器を順に実行。放射状探索は 220〜260 レイ |
| プレビュー画像生成 | マスクと輪郭線の RGBA バッファを毎回組み立てて `NSImage` 化 |
| デバッグ出力 | `contourDebugImageExport` が既定で `true`。PNG をディスクへ書き出す |

対策として最低限必要なもの:

- 抽出・色域選択・白フチ除去・詳細抽出を**バックグラウンドへ退避**し、進捗表示を出す
- ラスター解像度を可変にする（StarWindow も 640 → 1024 へ上げた経緯があり、品質と速度のトレードオフは調整済みの実績がある）
- 全面走査をやめ、選択範囲や ROI の bounding box に処理を限定する
  （`RasterPixelRect` という仕組みは既にあるので、適用範囲を広げる方向）
- **`AppDefaults.contourDebugLogging` / `contourDebugImageExport` を製品ビルドでは必ず `false` にする**

## 4.7 取り込みの進め方（提案）

[MVP](../product/mvp.md#mvp-のゴール) は「画像と図形でメモを作る」「Mac 上で使える」
「キーバインドで呼び出せる」の 3 つが揃った状態です。
**MVP に必要なものを先に、品質を上げるものを後に**並べると次の順になります。

### 第 1 段階: 土台（MVP 必須）

1. **macOS ターゲット化**
   qool の `UIKit` 依存 2 ファイルを AppKit へ寄せ、Mac で起動する状態を作る（[4.2](#42-プラットフォーム)）
2. **座標と輪郭の土台**
   `ContourSmoother` / `ContourPadding` / `RectangularGuideContour` を `Domain/Services` へ移植。
   純粋ロジックなので単体テストを書ける（StarWindow にはテストがないので、ここで初めて入る）
3. **`CanvasElement` の画像対応**
   画像参照・輪郭・調整パラメータを持てるようにする（[4.3](#43-qool-側のモデル拡張)）
4. **永続化**
   メモと画像アセットをディスクへ保存する（[4.4](#44-永続化)）。
   これがないと「作ったメモを後で呼び出す」が成立せず、MVP に届かない

### 第 2 段階: 切り抜きを実用にする（MVP 必須）

5. **画像の取り込みと手動切り抜き**
   `NSOpenPanel` + ドラッグ&ドロップ + 手描きなぞり → `ContourSmoother.polished()` だけで切り抜く。
   ここで qool の画像切り抜き画面がモックでなくなる
6. **輪郭候補の自動抽出**
   抽出器を 1 つずつ移植し、候補選択バーを追加。
   **被写体マスク（bias +0.55）と矩形補正の 2 つから始めるのが費用対効果が高い**

### 第 3 段階: Mac のメモとして使えるようにする（MVP 必須）

7. **任意形状のフローティングメモ**
   `CutoutWindowManager` / `CutoutMemoWindow` / `CutoutHostingView` を移植（[4.8](#48-mvp-のコアとして移植するもの)）
8. **グローバルホットキーでの呼び出し**
   StarWindow にも qool にも存在しない、**新規に設計が必要な唯一の MVP 要素**。
   要件（ユーザーがキーを設定できること / 設定 UI を自作できること）と実装方式の候補は
   [キーバインド設計](../product/hotkeys.md)を参照

ここまでで MVP 到達。

### 第 4 段階: 品質を上げる（MVP 後）

9. **ラスターマスク編集** — ペン / 消しゴム / 投げ縄
10. **仕上げ機能** — 色域選択 / 白フチ除去 / 部分詳細抽出 / 曲線ツール
11. **テキスト表示域** — `NSTextView.textContainer.exclusionPaths` で
    [spec.md](../spec.md) の「パスを用いて入力欄を設定できる」を実現する

## 4.8 MVP のコアとして移植するもの

**当初「macOS 固有だから移植しない」と整理していた出力部分は、[MVP](../product/mvp.md) の
「Mac 上で使えるメモ」そのものです。最優先で移植する対象になります。**

| 実装 | 役割 |
|------|------|
| `CutoutWindowManager` | borderless / 透明 / floating な `NSWindow` を開き、多重管理する |
| `CutoutMemoWindow` | `canBecomeKey` / `canBecomeMain` を持つ borderless ウィンドウ |
| `CutoutHostingView` | **輪郭多角形の内側でしかヒットテストを通さない**。外側のクリックは背面のアプリへ抜ける |
| `CutoutMemoWindowView` | 画像をマスクして表示し、`ShapedTextEditor` で本文を任意形状に流し込む |

qool へ持ってくるときの差分:

- StarWindow は**画像 1 枚 = ウィンドウ 1 つ**だが、qool は**キャンバス（図形 + 複数の切り抜き画像）
  = ウィンドウ 1 つ**になる。マスク輪郭は個々の切り抜きではなく、キャンバス全体の合成形状から作る
- キャンバスの Union 結果（`pathContours`）をそのままウィンドウ形状に使えると筋がよい
- ウィンドウ位置・サイズの永続化が要る（StarWindow は開くたびに画面中央から 24pt ずつずらすだけ）

## 4.9 移植しないもの

- `DebugContourExporter` — 開発時のみ。移植するとしても製品ビルドから除外する
  （`AppDefaults.contourDebugLogging` / `contourDebugImageExport` は既定で `true` なので注意）
- `MemoPaperView` の本文 `TextEditor` — StarWindow では画像に重ねた単一のテキスト入力だったが、
  qool ではキャンバス上の `.text` 要素とテキスト表示域がその役割を担う
