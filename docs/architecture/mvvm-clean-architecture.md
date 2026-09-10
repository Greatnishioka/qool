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
    Enums/          MemoPersistenceStatus / CanvasDragTarget / CutoutSheetTool
    Views/          メモパネル / キャンバス / 画像切り抜き / フローティングメモ / 設定
                    Components/  要素・キャンバス面・プロパティ・ツールドックなど
    ViewModels/     AppRootViewModel / CanvasViewModel
    Support/        CanvasColor+SwiftUI / RGBAComponents+SwiftUI
                    / CanvasImageStore / CutoutMaskStore / CutoutDrawingMask
                    / CutoutEditingBase / FloatingMemoPresenter / HotKeyCoordinator
  Application/
    UseCases/
      Memo/         Load / Create / Save / Delete / FlushMemos / ObserveWriteStates
                    / UpdateFloatingOrigin
      Canvas/       Move / Delete / Update / UpdateElements / Reorder / Resize
                    / UnionCanvasElements / BuildFloatingMemoOutline
      Image/        BuildCutoutCandidates / BuildCutoutContour / EditCutoutMask
                    / ImportImage / PruneImageAssets
  Domain/
    Enums/          CanvasElementKind / CanvasTool / CanvasColor / CanvasElementOrder
                    / CanvasResizeCorner / CanvasStrokeAlignment / ContourCandidateSource
                    / ContourEditMode / ImageBlurDirection / MemoWriteState
                    / HotKeyAction / VirtualKey
    Models/         Memo / Canvas / CanvasElement / CanvasElementSnapshot
                    / CanvasPathContour / NormalizedPoint / RGBAComponents
                    / ImageCutoutDraft / ImageAdjustment / FloatingMemoOutline
                    / ContourCandidate / CutoutCandidate / CutoutCrop
                    / CutoutImageSource / CutoutMask / CutoutMaskReference
                    / CutoutMaskEditHistory / HotKey 一式
    Coding/         各モデルの手書き Codable 実装
    Repositories/   MemoRepositoryProtocol / MemoWriteMonitoringProtocol
                    / ImageAssetRepositoryProtocol / AppSettingsProtocol
                    / CutoutMaskExtractorProtocol / MaskContourDeriverProtocol
                    / RegionMaskExtractorProtocol / GlobalHotKeyProtocol
    Services/       CanvasSelectionService / CanvasDraftElementBuilder
                    / CanvasElementPolygons / ContourGeometry / ContourHitTest
                    / ContourSmoother / ContourPadding / ContourCandidateSelector
                    / RectangularGuideContour / CutoutCropGeometry
                    / CutoutMaskFilters / CutoutMaskRasterizer / CutoutMaskStamp
    Support/        CGRect+UnitSpace / CGRect+UnitExtent（正規化座標のヘルパー）
  Infrastructure/
    Enums/          MemoWriteFailure / HotKeyRegistrationFailure
    Persistence/    MemoStorageLayout（ディスク上の配置）
                    / FileMemoRepositoryInfrastructure / InMemoryMemoRepositoryInfrastructure
                    / DebouncedMemoRepositoryInfrastructure
                    / FileImageAssetRepositoryInfrastructure
                    / UserDefaultsAppSettingsInfrastructure / CutoutMaskPNGCodec
    Vision/         SubjectMaskExtractorInfrastructure
    OpenCV/         GrabCutContourExtractorInfrastructure / MaskContourDeriverInfrastructure
                    / RegionFillExtractorInfrastructure
    AppKit/         フローティングメモウィンドウ / グローバルホットキー
                    / スクロールとスペースキーの入力
```

**画像編集は StarWindow から移植しました。** 向こうも同じレイヤ分割だったため、
配置先を考え直す必要はありませんでした（[取り込み計画](../image-editing/04-integration-plan.md#41-レイヤ配置)）。

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

`CanvasViewModel` は `CanvasSelectionService` / `CanvasDraftElementBuilder` /
`CutoutCropGeometry` などを UseCase を経由せず直接使っています。
図形の選択・描画といった純粋な操作なので実害は小さいものの、
`View → ViewModel → UseCase → Domain` の原則からは外れています。

### ~~`any` の表記ゆれ~~（解消）

`SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY` を有効にしたため、
存在型に `any` を付け忘れるとコンパイラが指摘します。

## ~~プラットフォーム~~（解消）

iOS / iPadOS ターゲットで、`CanvasSurface` が `UIPress` / `GameController` を、
`CanvasPropertiesPanel` が `UIColor` を使っていた状態は **macOS 専用へ作り直して解消しました。**
UIKit への依存はありません。
