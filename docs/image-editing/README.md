# 画像編集機能（StarWindow からの取り込み）

qool の[画像切り抜き](../features/03-image-cutout.md)・[画像調整](../features/04-image-adjustment.md)は
現在モック実装です。本実装は別リポジトリの検証用アプリ **StarWindow** で先行開発されており、
このディレクトリはその機能と、qool へ取り込むときの対応関係をまとめたものです。

- 出典: `/Users/nishioka/projects/ayato-dev/test_swift_ui`（`swift-memo-demo`）
- 対象コミット: `e5f79c3 スムース化の機能を強化 & マスクの解像度をアップ` + 未コミットの MVVM 分割
- 位置づけ: 検証用の使い捨てコード。リポジトリの README にも「製品版にする際は一から作り直す」と明記されています。
  **残すべきは「動くコード」ではなく「動くと分かったアルゴリズムと UI の設計判断」**です
  （[開発方針](../product/mvp.md#開発方針)）

## ドキュメント

| ファイル | 内容 |
|----------|------|
| [01-cutout-flow.md](01-cutout-flow.md) | 画像読み込み → なぞり → 候補抽出 → 候補選択 までの切り抜きフロー |
| [02-contour-extractors.md](02-contour-extractors.md) | 7 種類の輪郭抽出器、スコアリング、スムース化パイプライン |
| [03-adjustment-editor.md](03-adjustment-editor.md) | メモ調整画面（表示範囲修正、5 ツール、ラスターマスク、テキスト表示域） |
| [04-integration-plan.md](04-integration-plan.md) | qool への取り込み計画、対応表、移植時の課題 |

## StarWindow とは

macOS 向けの Swift Package 実行ファイル（AppKit + SwiftUI + Vision + CoreImage、外部依存なし）です。

> 画像からメモ用紙やキャラクター付きメモの表示範囲を抽出し、任意形状のメモウィンドウとして表示する

という単体アプリで、以下の流れになっています。

```text
画像を読み込む
  → 被写体・紙の外周を大まかになぞる
  → 7 種類の抽出器が輪郭候補を生成
  → スコア順に候補を提示、ユーザーが選ぶ
  → 「メモ化」で調整シートを開く
  → 表示範囲・透明度・明度・余白・ぼかし・テキスト表示域を調整
  → 任意形状のフローティングウィンドウとして開く
```

**このフロー全体が qool の取り込み対象です。**

最後の「任意形状のフローティングウィンドウ」も例外ではありません。
[MVP](../product/mvp.md#mvp-のゴール) の「Mac 上で使えるメモ」がまさにこれにあたるため、
切り捨てるどころか**最優先で移植する部分**になります（[4.8](04-integration-plan.md#48-mvp-のコアとして移植するもの)）。

qool は macOS アプリとして作り直す前提なので、
StarWindow の AppKit 実装は書き換えずにほぼそのまま活かせます。

## qool の画面との対応

| qool の画面 / MVP 要件 | StarWindow の相当機能 |
|------------------------|----------------------|
| [画像切り抜き](../features/03-image-cutout.md) | `MemoPaperView` のなぞり + 輪郭候補抽出・選択バー |
| [画像調整](../features/04-image-adjustment.md) | `MemoCreationPreviewSheet` の表示範囲編集・各種スライダー |
| キャンバスの「パスで入力欄を設定」（[spec.md](../spec.md) の未実装項目） | `MemoPreviewConfiguration.textPath` + `ShapedTextEditor` |
| **MVP:「Mac 上で使えるメモ」** | `CutoutWindowManager` の任意形状フローティングウィンドウ |
| **MVP:「キーバインドで呼び出せる」** | **相当機能なし。新規設計が必要** |

## 共通の前提

- **座標はすべて画像内の正規化座標 `0...1` の `CGPoint`**。qool の `NormalizedPoint` と同じ考え方です
- y 軸は上から下（SwiftUI/AppKit の描画座標系）。Vision の座標系とは内部で変換しています
- 自動テストはありません
- `AppDefaults` に 80 個以上のチューニング定数が集約されています
