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

型の配置と命名の規約は [コード配置と命名の規約](code-organization.md) が定義しています。
ここではレイヤの対応だけを示します。

```text
qool/
  App/              QoolApp（@main） / AppDelegate（合成ルート）
  Presentation/
    Enums/          MemoPersistenceStatus / CanvasDragTarget
    Views/          メモパネル / キャンバス / 画像切り抜き / 画像調整（後者 3 つは未実装）
    ViewModels/     AppRootViewModel / CanvasViewModel
    Support/        CanvasColor+SwiftUI / RGBAComponents+SwiftUI
  Application/
    UseCases/
      Memo/         Load / Create / Save / FlushMemos / ObserveWriteStates
      Canvas/       Move / Delete / Update / UpdateElements / UnionCanvasElements
                    + 輪郭候補の抽出 / マスク編集 / 切り抜き画像の書き出し（追加予定）
  Domain/
    Enums/          CanvasElementKind / CanvasTool / CanvasColor / MemoWriteState
                    / ImageBlurDirection
    Models/         Memo / Canvas / CanvasElement / CanvasElementSnapshot
                    / CanvasPathContour / NormalizedPoint / RGBAComponents
                    / ImageCutoutDraft / ImageAdjustment
                    + ContourCandidate / RasterContourMask / RasterSelectionMask（追加予定）
    Coding/         各モデルの手書き Codable 実装
    Repositories/   MemoRepositoryProtocol / MemoWriteMonitoringProtocol
                    / ImageAssetRepositoryProtocol
    Services/       CanvasElementFactory / CanvasSelectionService / CanvasDraftElementBuilder
                    / ContourSmoother / ContourPadding / RectangularGuideContour
                    + ContourCandidateSelector / ContourQualityValidator
                      / CurvePathBuilder（追加予定）
    Support/        CGRect+UnitSpace（正規化座標のヘルパー）
  Infrastructure/
    Enums/          MemoWriteFailure
    Persistence/    MemoStorageLayout（ディスク上の配置）
                    / FileMemoRepositoryInfrastructure / InMemoryMemoRepositoryInfrastructure
                    / DebouncedMemoRepositoryInfrastructure
                    / FileImageAssetRepositoryInfrastructure
    Vision/         SubjectMaskExtractor / PreprocessedContourExtractor / ContourDetector（追加予定）
    CoreImage/      GuidedBackgroundContourExtractor / LineColorContourExtractor
                    / ColoredPaperRectangleExtractor / CutoutImageRenderer（追加予定）
    AppKit/         フローティングメモウィンドウ / グローバルホットキー（追加予定）
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

**資料として正確を期すため、方針に沿っていない箇所を挙げます。**
[クラッシュアンドビルド方針](../product/mvp.md#開発方針)なので急いで直す必要はありませんが、
作り直しの際に繰り返さないための記録です。解消したものは取り消し線で残しています。

### ~~Domain が SwiftUI に依存している~~（Phase 0 で解消）

`Canvas.swift` が `import SwiftUI` し `CanvasColor.swiftUIColor: Color` を持っていた問題は、
**Phase 0 で解消しました。**

- Domain は [`RGBAComponents`](../../qool/Domain/Models/RGBAComponents.swift) として色の成分だけを持つ
- `Color` への変換は Presentation の
  [`CanvasColor+SwiftUI`](../../qool/Presentation/Support/CanvasColor%2BSwiftUI.swift) が担う

### DI の口がない

- `AppRootViewModel.bootstrap()` がリポジトリの組み立てを直接持っている
- `CanvasViewModel` の `init` が UseCase / Service をデフォルト引数で自前生成している

差し替えは可能な形にはなっていますが、組み立てを一箇所に集約する仕組みはありません。

### ViewModel が Domain サービスを直接呼んでいる

`CanvasViewModel` は `CanvasElementFactory` / `CanvasSelectionService` / `CanvasDraftElementBuilder` を
UseCase を経由せず直接使っています。図形の選択・描画といった純粋な操作なので実害は小さいものの、
`View → ViewModel → UseCase → Domain` の原則からは外れています。

### ~~`any` の表記ゆれ~~（解消）

`SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY` を有効にしたため、
存在型に `any` を付け忘れるとコンパイラが指摘します。

### StarWindow 側の import

移植元の全ファイルが機械的に `import AppKit / CoreImage / SwiftUI / UniformTypeIdentifiers / Vision` を
書いています。**Domain 相当のファイルも例外ではない**ため、移植時に不要な import の除去が必要です
（中身は `CGPoint` / `CGRect` しか使っていないので、除去するだけで済みます）。

## プラットフォーム

qool は現在 iOS / iPadOS ターゲットですが、[MVP](../product/mvp.md) は Mac 上で動くことを前提としており、
**macOS アプリとして作り直す方針**です。

UIKit に依存しているのは以下の 2 ファイルのみで、影響範囲は限定的です。

- [`CanvasSurface.swift`](../../qool/Presentation/Views/Components/CanvasSurface.swift) — `UIPress` / `GameController` による Shift キー検出
- [`CanvasPropertiesPanel.swift`](../../qool/Presentation/Views/Components/CanvasPropertiesPanel.swift) — `UIColor` による色成分の取得

いずれも Presentation 層にあり、Domain / Application は UIKit に依存していません。
