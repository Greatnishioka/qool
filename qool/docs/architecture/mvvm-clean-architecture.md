# アーキテクチャ（MVVM + Clean Architecture）

## 依存方向

```text
View  →  ViewModel  →  UseCase  →  Domain
                                     ↑
                          Infrastructure（protocol を実装）
```

- 内側（Domain）は外側を知らない
- Infrastructure は Domain が定義した protocol を実装する形で外側から刺さる
- View は ViewModel だけを見る。UseCase や Infrastructure を直接触らない

## ディレクトリ構成

現在の構成と、[画像編集機能](../image-editing/README.md)を取り込んだ後の想定です。

```text
qool/
  Presentation/
    Views/            メモ一覧 / キャンバス / 画像切り抜き / 画像調整
    ViewModels/       AppRootViewModel / CanvasViewModel
  Application/
    UseCases/         CanvasEditingUseCases / CanvasUnionUseCase / MemoUseCases
                      + 輪郭候補の抽出 / マスク編集 / 切り抜き画像の書き出し（追加予定）
  Domain/
    Models/           Memo / Canvas / CanvasElement / ImageMemoWorkflow
                      + ContourCandidate / RasterContourMask / RasterSelectionMask（追加予定）
    Repositories/     MemoRepository（protocol）
                      + ImageAssetRepository（追加予定）
    Services/         CanvasElementFactory / CanvasSelectionService / CanvasDraftElementBuilder
                      + ContourSmoother / ContourPadding / ContourCandidateSelector
                        / ContourQualityValidator / RectangularGuideContour / CurvePathBuilder（追加予定）
  Infrastructure/
    Persistence/      InMemoryMemoRepository（→ ファイル永続化へ差し替え予定）
    Vision/           SubjectMaskExtractor / PreprocessedContourExtractor / ContourDetector（追加予定）
    CoreImage/        GuidedBackgroundContourExtractor / LineColorContourExtractor
                      / ColoredPaperRectangleExtractor / CutoutImageRenderer（追加予定）
    AppKit/           フローティングメモウィンドウ / グローバルホットキー（追加予定）
```

追加予定のものは StarWindow 側で同じレイヤ分割がすでに済んでいるため、
**配置先を考え直す必要はなく、そのまま対応する場所へ移せます**（[取り込み計画](../image-editing/04-integration-plan.md#41-レイヤ配置)）。

## レイヤごとの責務

| レイヤ | 責務 | 依存してよいもの |
|--------|------|------------------|
| Presentation | 画面の描画とユーザー入力の受け取り、表示用の状態保持 | SwiftUI / AppKit、ViewModel |
| Application | ユースケース単位の手続き。複数の Domain サービスを束ねる | Domain |
| Domain | モデルとビジネスロジック。**フレームワークに依存しない** | Foundation / CoreGraphics のみ |
| Infrastructure | 外界との接続（永続化、Vision、CoreImage、ウィンドウ、ファイル） | Domain の protocol |

## 現状の逸脱

**資料として正確を期すため、現時点で上記の方針に沿っていない箇所を挙げます。**
[クラッシュアンドビルド方針](../product/mvp.md#開発方針)なので、いま直す必要はありませんが、
作り直しの際に繰り返さないための記録です。

### Domain が SwiftUI に依存している

[`Canvas.swift`](../../Domain/Models/Canvas.swift) が `import SwiftUI` し、
`CanvasColor.swiftUIColor: Color` を持っています。**Domain が UI フレームワークに依存する形**です。

色は Domain では RGBA の値として持ち、Presentation 側の extension で `Color` へ変換するのが本来の形です。
StarWindow には同じ目的の [`RGBColor`](../image-editing/02-contour-extractors.md) がフレームワーク非依存で定義されており、そちらが参考になります。

### DI の口がない

- `AppRootViewModel.bootstrap()` が `InMemoryMemoRepository` を直接生成している
- `CanvasViewModel` の `init` が UseCase / Service をデフォルト引数で自前生成している

差し替えは可能な形にはなっていますが、組み立てを一箇所に集約する仕組みはありません。
永続化を実装に差し替える段で必要になります。

### ViewModel が Domain サービスを直接呼んでいる

`CanvasViewModel` は `CanvasElementFactory` / `CanvasSelectionService` / `CanvasDraftElementBuilder` を
UseCase を経由せず直接使っています。図形の選択・描画といった純粋な操作なので実害は小さいものの、
`View → ViewModel → UseCase → Domain` の原則からは外れています。

### StarWindow 側の import

移植元の全ファイルが機械的に `import AppKit / CoreImage / SwiftUI / UniformTypeIdentifiers / Vision` を
書いています。**Domain 相当のファイルも例外ではない**ため、移植時に不要な import の除去が必要です
（中身は `CGPoint` / `CGRect` しか使っていないので、除去するだけで済みます）。

## プラットフォーム

qool は現在 iOS / iPadOS ターゲットですが、[MVP](../product/mvp.md) は Mac 上で動くことを前提としており、
**macOS アプリとして作り直す方針**です。

UIKit に依存しているのは以下の 2 ファイルのみで、影響範囲は限定的です。

- [`CanvasSurface.swift`](../../Presentation/Views/Components/CanvasSurface.swift) — `UIPress` / `GameController` による Shift キー検出
- [`CanvasPropertiesPanel.swift`](../../Presentation/Views/Components/CanvasPropertiesPanel.swift) — `UIColor` による色成分の取得

いずれも Presentation 層にあり、Domain / Application は UIKit に依存していません。
