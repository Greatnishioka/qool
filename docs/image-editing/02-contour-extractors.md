# 2. 輪郭抽出器とスコアリング

StarWindow の中核。ユーザーのなぞり（ガイド）を手がかりに、
**7 種類の独立した抽出器**が輪郭候補を生成し、共通のスコアで順位付けします。

## 抽出器の一覧

| ソース | 実装 | 手法 | bias |
|--------|------|------|------|
| 被写体 `subjectMask` | `SubjectMaskExtractor` (Vision) | Vision の foreground instance mask から被写体マスクを生成 | **+0.55** |
| 前処理 `preprocessedContour` | `PreprocessedContourExtractor` (Vision + CoreImage) | Core Image で二値化寄りに前処理してから Vision contours | +0.24 |
| 背景差分 `backgroundDifference` | `GuidedBackgroundContourExtractor` (CoreImage) | ガイド外側から背景色を推定し、背景との差で放射状に境界を探す（220 レイ） | 0 |
| 線色 `lineColorContour` | `LineColorContourExtractor` (CoreImage) | なぞり線の近くから内側へ、明るい有彩色の枠線を追跡（260 レイ） | +0.08 |
| 色矩形 `coloredRectangle` | `ColoredPaperRectangleExtractor` (CoreImage) | 色付き付箋のような矩形領域を検出 | -0.04 |
| 矩形補正 `rectangularGuide` | `RectangularGuideContour` (純ロジック) | ガイドが矩形らしければ矩形に整える | -0.18 |
| Vision `rawVisionContour` | `ContourDetector` (Vision) | Vision contours の生検出（フォールバック） | +0.12 |

`bias` はスコアに直接加算される優先度です。Vision の被写体マスクが最優先、
矩形補正は「他に何もなければ」という位置づけになっています。

これに加えて、UI 側で必ず **「手描き」**（なぞり線をそのまま整形したもの）が候補末尾に足されます。

### smoothsContour フラグ

候補ごとに、表示前に `ContourSmoother.polished()` をかけるかどうかが決まっています。

- かける: 被写体 / 前処理 / 背景差分 / 線色 / Vision
- かけない: 色矩形 / 矩形補正（すでに直線的な形状なので、平滑化すると角が丸まってしまう）

## スコアリング

`ContourCandidateSelector.score(_:guide:)`。まず**足切り条件**を全部満たさないと候補になりません（`nil`）。

| 条件 | 閾値 |
|------|------|
| 輪郭の点数 | 8 点以上（ガイドは 3 点以上） |
| bounds の重なり率 `overlap` | `minimumDetectionGuideOverlap` = 0.62 以上 |
| ガイド内部に入っている点の割合 `inside` | 0.58 以上 |
| 面積比 `areaRatio`（候補 ÷ ガイド） | 候補ごとの `minimumAreaRatio` 以上、かつ 1.48 以下 |
| 中心距離 / ガイド対角長 | 0.28 以下 |

通過したものに対して:

```text
score = overlap      * 0.95
      + inside       * 0.75
      + centerScore  * 0.55      // 中心が近いほど 1 に近づく
      + areaScore    * 0.55      // 面積比 0.35〜1.0 が満点、外れるほど減点
      + source.bias
      - compactnessPenalty       // 背景差分が bounds をほぼ埋めている場合 -0.18
```

`compactnessPenalty` は「背景差分が画像全体を拾ってしまった」ケースを弾くための補正です。

**`AppDefaults.minimumAutoCandidateScore` = 2.05 を超えた候補の最高得点が推奨候補**になります。
超えるものがなければ推奨は「手描き」になります。

## 品質バリデーション

`ContourQualityValidator.isAcceptable(_:guide:minimumAreaRatio:)` はスコアリングとは別の、
より厳しめの合否判定です（`applyDetectedContour` のフォールバック判定で使用）。

- 重なり率 0.62 以上
- 面積比 `minimumAreaRatio` 〜 1.45
- 中心距離 / 対角長 0.24 以下

不合格なら「なぞり線を整形したもの」へフォールバックします。

## スムース化パイプライン

> **移植済み。** [`ContourSmoother`](../../qool/Domain/Services/ContourSmoother.swift) /
> [`ContourPadding`](../../qool/Domain/Services/ContourPadding.swift) /
> [`RectangularGuideContour`](../../qool/Domain/Services/RectangularGuideContour.swift) は qool にあります。
> 選択範囲限定のスムース化とデバッグ出力は、依存する `RasterSelectionMask` が
> 第 4 段階の型のため持ってきていません。

`ContourSmoother` が輪郭の見た目を決めています。`polished(_:)` は 5 段構成です。

```text
densify(maxSegmentLength: 0.012)   点列を等間隔に増やす
  → removeSpikes                    飛び出したトゲを除去（2 回、角度48°/距離2.15倍が閾値）
  → straightenLineRuns              ほぼ直線の区間（7点窓・10°以内・30点以上）を直線に寄せる（強度 0.86）
  → roundCorners                    角を丸める
  → smooth (smoothClosedByAnchors)  角アンカーを保護しつつ区間ごとに平滑化
```

### 角アンカーの保護

単純に全体を平滑化すると、紙の角のような**残すべき角まで丸まってしまう**ため、
以下の仕組みで角を守っています。

- 曲がり角の角度が `contourSmoothingAnchorAngleDegrees` = 150° より鋭い点をアンカーとして検出
- **アンカー検出は元のパスではなく、`contourCornerDetectionResamplePixels` = 10px 相当で粗く再サンプリングしたパスに対して行う**
  （元パスのギザギザを角と誤検出しないため）
- アンカー同士の最小間隔 18px
- アンカーの前後 `contourSmoothingAnchorProtectionPixels` = 3px は平滑化しない
- アンカーで区切られた区間のうち 8 点以上あるものだけを平滑化（`contourSmoothingIterations` = 3、強度 0.35）

### 選択範囲限定のスムース化

`smoothForEditing(_:limitingTo:)` は投げ縄／色域選択がある場合に使われ、
**選択範囲に入っている連続区間だけ**を「開いたパス」として平滑化します。
選択がなければ通常の `smooth()` と同じです。

### デバッグ出力

`smoothingDebugInfo(for:limitingTo:)` がアンカー位置・保護範囲・平滑化対象区間を返し、
`DebugContourExporter` が画像に重ねた PNG を `debug-contours/` へ書き出します。
アンカー検出のチューニングはこの出力を見ながら行われています。

## 移植時に判明した挙動

移植にあたって、同じ入力に対する出力が **移植元と 12 桁まで一致する**ことを確認しました
（矩形 / 真円 / ノイズ入りの輪郭 / パディングの正負など 9 ケース、3038 行の数値を突き合わせ）。
そのうえで単体テストを書いた結果、**書かれていなかった挙動が 2 つ**見つかりました。
どちらも StarWindow と共通で、qool 側で変えてはいません。

### 大きな滑らかな輪郭は直線化に巻き込まれて潰れる

`straightenLineRuns` は「3 点ぶんの曲がりが 10 度未満」の区間を直線とみなします。
半径が大きい円ほど曲がりは緩いため、**円周全体が 1 本の直線区間と判定され、
最小二乗直線へ強度 0.86 で寄せられます。**

正規化座標の真円で測ると、半径 0.15 は保たれ（99%）、0.18 では中心付近まで潰れます
（最小半径が元の 14%）。閾値は半径だけでなく `densify` 後の点間隔にも依存します。

実際の写真から取れる輪郭はガタついていて判定を通らないため、**現状で実害は出ていません。**
ただし解析的に滑らかな輪郭（楕円フィットの結果など）を `polished()` に渡すと壊れます。

### `polished()` はトゲを落とさない

`removeSpikes` がトゲとみなすのは「隣との距離が中央値の 2.15 倍を超える点」です。
ところが `polished()` は **`densify` を先に通す**ため、トゲへ伸びる長い辺が分割され、
長さの条件に掛からなくなります。半径 0.25 の輪郭に 0.5 まで飛び出した点を作っても、
`polished()` 後もほぼそのまま残ります。

角度の条件（`contourSpikeAngleDegrees` = 48 度）も、判定が
「前後へのベクトルがなす角が 132 度を超えたら」なので、
**トゲの先端（前後へのベクトルがほぼ同じ向き）ではなく、ほぼ直線上の点に当たります。**

## 余白（パディング）

`ContourPadding.expanded(_:imageSize:paddingPixels:)` が輪郭を外側へ膨らませます。

- **矩形らしい輪郭**（`RectangularGuideContour.isRectangleLikeContour`）の場合は
  bounds を `insetBy` して矩形として作り直す（角が崩れないように）
- それ以外は重心から各点への方向へ `paddingPixels` だけ押し出す

負の値を渡せば収縮になります。マスク生成時は `contourMaskInsetPixels` = 3px 分だけ内側に寄せて、
白フチが出にくいようにしています。
