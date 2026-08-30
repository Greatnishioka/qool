# コード配置と命名の規約

型の置き場所・命名・コメントの粒度を決める。
レイヤの責務と依存方向は [MVVM + Clean Architecture](mvvm-clean-architecture.md) が定義しており、
**この資料はその内側で「1 つの型をどのファイルに置き、何と名付けるか」だけを決める。**

対象は既存の 22 ファイル / 45 型。移行手順は末尾の[移行計画](#移行計画)にある。

**移行は完了している。** 3 つのコミットで適用済みで、以降はこの規約に従って書く。

## 決定

| # | 規約 | 適用範囲 |
|---|------|----------|
| 1 | 1 ファイル 1 型。ファイル名は型名と一致させる | 全レイヤ |
| 2 | enum はレイヤ内の `Enums/` に集める | 全レイヤ |
| 3 | protocol は `~Protocol` で終える | 全レイヤ |
| 4 | Infrastructure の実装は `~Infrastructure` で終える。役割語（`Repository` など）は残す | Infrastructure |
| 5 | UseCase は 1 ファイル 1 個。`callAsFunction` で呼ぶ | Application |
| 6 | コメントは「コードから読み取れないこと」だけを書く | 全レイヤ |

規約 1 には[例外](#1-ファイル-1-型を適用しないもの)がある。機械的に適用すると情報が減る箇所があるため、
**どこに適用しないかまで決めておく。**

---

## 1. enum の置き場所

レイヤの中に `Enums/` を切る。`Domain/Enums/` と `Presentation/Enums/` が並ぶ形になる。

トップレベルに `qool/Enums/` を 1 つ置く案は採らなかった。探すのは速いが、
`CanvasElementKind`（Domain）と `MemoPersistenceStatus`（Presentation）が同居し、
**Presentation の enum を Domain が参照しても、ディレクトリを見ただけでは違反に見えなくなる。**
依存方向はこのプロジェクトで唯一コンパイラが守ってくれない制約なので、
Domain のローカル Swift Package 化（境界を強制できるが全メンバーに `public` が要る）を
保留している間は、ディレクトリで見えるようにしておく。

### 移す enum

| 型 | 現在地 | 移動先 |
|----|--------|--------|
| `CanvasElementKind` | `Domain/Models/Canvas.swift:121` | `Domain/Enums/CanvasElementKind.swift` |
| `CanvasTool` | `Domain/Models/Canvas.swift:131` | `Domain/Enums/CanvasTool.swift` |
| `CanvasColor` | `Domain/Models/Canvas.swift:142` | `Domain/Enums/CanvasColor.swift` |
| `MemoWriteState` | `Domain/Repositories/MemoWriteMonitoring.swift:8` | `Domain/Enums/MemoWriteState.swift` |
| `DebouncedMemoRepository.WriteFailure` | ネスト | `Infrastructure/Enums/MemoWriteFailure.swift` |
| `AppRootViewModel.PersistenceStatus` | ネスト | `Presentation/Enums/MemoPersistenceStatus.swift` |

`WriteFailure` と `PersistenceStatus` はネストを解く。どちらも `internal` で型の外へ出ていくため、
**ネストしていることが実装の詳細を示していない。** 名前は外へ出しても意味が通るように付け替える
（`PersistenceStatus` は単独だと汎用すぎる。画像アセットの永続化が入ると衝突する）。

---

## 2. 1 ファイル 1 型

### 分割するファイル

**`Domain/Models/Canvas.swift`（212 行 / 7 型）**

```text
Canvas.swift                  Canvas のみ残す
CanvasElement.swift           ← :12
CanvasElementSnapshot.swift   ← :61
CanvasPathContour.swift       ← :111
Enums/CanvasElementKind.swift ← :121
Enums/CanvasTool.swift        ← :131
Enums/CanvasColor.swift       ← :142
```

**`Domain/Models/ImageMemoWorkflow.swift`（3 型）**

```text
ImageCutoutDraft.swift  ImageAdjustment.swift  NormalizedPoint.swift
```

ファイル名の `ImageMemoWorkflow` はどの型とも対応していない。分割で消える。

**`Domain/Models/CanvasCoding.swift`（4 型の Codable 実装）**

`Domain/Coding/` を切り、型ごとに分ける。`Models/` の下に置かないのは、
`CanvasColor+Codable` の対象が `Enums/` にあるため。

```text
Domain/Coding/RGBAComponents+Codable.swift
Domain/Coding/CanvasColor+Codable.swift
Domain/Coding/CanvasElement+Codable.swift
Domain/Coding/CanvasElementSnapshot+Codable.swift
```

先頭の「なぜ合成 `Codable` に任せないか」（10 行）は、
各ファイルの先頭 1 行（人が読める JSON / 欠けたキーを既定値で埋める / 復号時も不変条件を通す）に圧縮する。

`CanvasElement.CodingKeys` は現在 `fileprivate` だが、
使うのは `CanvasElement+Codable.swift` の中だけなので分割しても壊れない
（`CanvasElementSnapshot` は `CanvasElement(from:)` を呼ぶだけで、キーには触れていない）。
分割時に `private` へ狭める。

**`Presentation/Support/CanvasColor+SwiftUI.swift`（2 型の extension）**

```text
CanvasColor+SwiftUI.swift  RGBAComponents+SwiftUI.swift
```

**`qoolApp.swift`（`AppDelegate` + `QoolApp`）**

`qool/App/` を切って分ける。`AppDelegate` は合成ルート（ViewModel を所有し、終了時の flush を持つ）で、
`@main` の宣言とは責務が別。

```text
App/QoolApp.swift  App/AppDelegate.swift
```

### 1 ファイル 1 型を適用しないもの

**`private` なネスト型は出さない。** 別ファイルへ移すには可視性を広げる必要があり、
**`private` であること自体が持っていた「これは実装の詳細」という情報が消える。**

| 型 | 置いたまま |
|----|-----------|
| `DebouncedMemoRepository` の `Mutation` / `PendingMutation` / `FailureOutcome` / `State` | ○ |
| `FileMemoRepository` の `StoredMemo` / `FileName` | ○ |
| `CanvasElement` / `RGBAComponents` / `CanvasColor` の `CodingKeys`、`CanvasColor.Preset` | ○ |
| テストの fake（`CountingMemoRepository` など）とその `State` / `TestError` | ○ |

**protocol の default 実装 extension は protocol と同じファイルに置く。**
`MemoRepositoryProtocol.flush()` の既定実装は契約の一部で、
分けると「実装しなくてよい」という情報が protocol を読んだだけでは分からなくなる。

---

## 3. protocol の命名

| 現在 | 変更後 | 出現数 |
|------|--------|--------|
| `MemoRepository` | `MemoRepositoryProtocol` | 19 |
| `MemoWriteMonitoring` | `MemoWriteMonitoringProtocol` | 4 |
| `ImageAssetRepository` | `ImageAssetRepositoryProtocol` | 3 |

ファイル名も型名に合わせる。テストの fake 3 個（`CountingMemoRepository` ×2 / `ControllableRepository`）は
準拠先の記述が変わるだけで、名前は変えない。

副作用として `any MemoRepository` の表記ゆれ（`any` 付き 2 / なし 5）を一括で揃えられる。
**この機会に `ExistentialAny` を有効化して、以後は機械的に強制する。**

---

## 4. Infrastructure の命名

`~Infrastructure` で終える。役割語（`Repository`）は残す。

接尾辞が付くのは **Domain の protocol を実装する型**です。
`MemoStorageLayout` のような層内部のヘルパーは、素の名前のままにします
（`MemoStorageLayoutInfrastructure` は読みにくく、得るものがありません）。

| 現在 | 変更後 |
|------|--------|
| `FileMemoRepository` | `FileMemoRepositoryInfrastructure` |
| `InMemoryMemoRepository` | `InMemoryMemoRepositoryInfrastructure` |
| `DebouncedMemoRepository` | `DebouncedMemoRepositoryInfrastructure` |

役割語を落とす案（`FileMemoInfrastructure`）は短いが、
[取り込み計画](../image-editing/04-integration-plan.md)で `Infrastructure/Vision/` と
`Infrastructure/CoreImage/` に抽出器・レンダラが 7 個入る予定で、
**そのとき「何の実装か」が接尾辞から消える。** 長さより対応関係を採る。

対応するテストのファイル名も追随する（`FileMemoRepositoryTests.swift` →
`FileMemoRepositoryInfrastructureTests.swift`）。

---

## 5. UseCase

1 ファイル 1 UseCase。呼び出しは `callAsFunction` に統一し、`execute` は消す。

```swift
nonisolated struct SaveMemoUseCase {
    let repository: any MemoRepositoryProtocol

    @discardableResult
    func callAsFunction(_ memo: Memo) async throws -> Memo { ... }
}

// 呼び出し側
let savedMemo = try await saveMemoUseCase(memo)
```

共通の `UseCaseProtocol` は作らない。`async throws` の有無、`inout` の有無、戻り値が
5 通りに割れており、**1 つの `associatedtype` 付き protocol にまとめると
呼び出し側から見て型が読みにくくなるだけで、得るものがない。**

### 分割後の一覧

`Application/UseCases/Memo/`

| ファイル | 由来 |
|----------|------|
| `LoadMemosUseCase.swift` | `MemoUseCases.swift:26` |
| `CreateMemoUseCase.swift` | `:34` |
| `SaveMemoUseCase.swift` | `:45` |
| `FlushMemosUseCase.swift` | `:7` |
| `ObserveWriteStatesUseCase.swift` | `:18` |

`Application/UseCases/Canvas/`

| ファイル | 由来 |
|----------|------|
| `MoveCanvasElementsUseCase.swift` | `CanvasEditingUseCases.moveElements` |
| `DeleteCanvasElementsUseCase.swift` | `.deleteElements` |
| `UpdateCanvasElementUseCase.swift` | `.updateElement` |
| `UpdateCanvasElementsUseCase.swift` | `.updateElements` |
| `UnionCanvasElementsUseCase.swift` | `CanvasUnionUseCase`（改名のみ） |

### 分割で決まること 2 つ

**`MoveCanvasElementsUseCase` は `UpdateCanvasElementsUseCase` を保持する。**
移動処理は「全選択要素の frame をずらす」を 2 回呼んでおり、これが `updateElements` そのもの。
プロパティとして持たせ、`init` の既定引数で組み立てる（他の UseCase と同じ形）。

**`MoveCanvasElementsUseCase` の `selectedElementsFrame` は消して `CanvasSelectionService` を使う。**
`CanvasEditingUseCases.swift:67-82` と `CanvasSelectionService.swift:34-46` は同じ実装が 2 つある。
分割時に Domain 側へ寄せる。

### 今回やらないこと

`UnionCanvasElementsUseCase` は 305 行のうち約 240 行が幾何計算（円弧・二次ベジエのサンプリング）で、
Domain サービスへ出せば単体テストが書ける。**が、今回は出さない。**
[取り込み計画](../image-editing/04-integration-plan.md)で StarWindow から `CurvePathBuilder` が
`Domain/Services/` に入る予定で、**曲線のサンプリングはそれと重複する。**
移植時に統合するほうが、抽出 → 破棄の往復より安い。改名だけ行い、中身は据え置く。

---

## 6. コメント

### 3 つのルール

1. **コードを読めば分かることは書かない。** 「〜する関数」「〜の場合」は消す
2. **3 行以上のブロックは結論 1〜2 行に圧縮し、残りは削除する。** `docs/` へは移さない
3. **残すのは、不変条件・失敗時の振る舞い・過去に踏んだ失敗・呼び出し規約**

`docs/` に置くのは設計判断だけで、コードの解説の避難先にはしない。
判断そのものは 1〜2 行に収まる。**収まらない部分は「どう動くか」の説明であり、
コードを読めば分かるので消してよい。**

### 圧縮する長いブロック（3 行以上は 38 箇所、うち長いもの）

| 場所 | 行数 | 圧縮後に残す内容 |
|------|------|------------------|
| `DebouncedMemoRepository.swift:4-31` | 28 | まとめ・直列化・有限回リトライのデコレータであること。保留をジョブの列ではなく ID ごとの「あるべき状態」で持つ理由（削除済みメモの復活） |
| `FileMemoRepository.swift:4-22` | 19 | 1 メモ = 1 ディレクトリで被害を局所化すること。`@unchecked Sendable` の根拠 |
| `ImageAssetRepository.swift:3-14` | 12 | 未実装であること。`CanvasElement` が画像の実体ではなく `UUID` を持つ理由 |
| `qoolApp.swift:4-14` | 11 | `.terminateLater` で終了を保留し、書き込み後に `reply` すること |
| `CanvasCoding.swift:4-13` | 10 | 合成 `Codable` を使わない 3 つの理由（各ファイル先頭に 1 行） |
| `MemoWriteMonitoring.swift:17-24` | 8 | まとめ書きをする実装だけが持つこと。購読者は 1 つだけ |
| `MemoRepository.swift:6-13` | 8 | `loadMemos()` を同期のままにしている理由 |

**判断は 1〜2 行で全部残る。** 消えるのは、その判断に至る経緯の再現（
「以前は `DispatchSemaphore` で待っていたが…」「ジョブとして積むと `save(A) 失敗 → delete(A) → …`」）で、
**これは [MEMORY](../../.claude/projects/-Users-nishioka-Desktop-qool/memory/qool-persistence-decisions.md)
に既にある。**

### 削除するコメント

| 場所 | 内容 |
|------|------|
| `CanvasElementFactory.swift` | 行コメント 8 個すべて。`case .rectangle` に「矩形 (四角形) の場合。」など、`switch` を日本語で読み上げているだけ |
| `CanvasViewModel.swift` | 行コメント 25 行のうち 23 行。「選択をクリアする関数。全部削除。」「距離計算関数。」など。`:61` の「洗濯用の枠」を含む |
| `CanvasCoding.swift:29` | 「containerはjsonなのか、plistなのか…」— `Codable` の一般論であってこのコードの説明ではない |

`CanvasViewModel` で**残す 2 行**は `:122`「3点以上ある場合かつ、最初の点の近くに点を置くと、パスを閉じる」
（18pt という閾値の意図がコードから読めない）と `:463`「パスが3点以下の場合は…」だけ。

`CanvasElementFactory` の `case .image` にある「現時点では、未実装」は残す。
**これは事実の記録で、コードからは読み取れない。**

---

## 移行計画

Xcode プロジェクトは `objectVersion = 77` の
`PBXFileSystemSynchronizedRootGroup` を使っている。
**ファイルの追加・移動・改名で `project.pbxproj` を編集する必要はない。**
ディレクトリを操作すればビルド対象に反映される。

各コミットの前に必ずテストを通す。UI テスト（`qoolUITests`）は
メニューバーアプリの起動待ちが返らずハングするため、`-only-testing:qoolTests` で除外する。

| # | 内容 | 性質 |
|---|------|------|
| 1 | 改名（protocol → `~Protocol`、Infrastructure → `~Infrastructure`）と型の分割・`Enums/` への移動を一度に | 挙動ゼロ。宣言の移動と 1 行置換だけ |
| 2 | UseCase の分割と `callAsFunction` 化。呼び出し側 2 ファイルを追随。重複した `selectedElementsFrame` を削除 | 唯一、挙動を変えうる |
| 3 | コメントの整理、`mvvm-clean-architecture.md` の構成更新、`ExistentialAny` の有効化 | コードの意味は変えない |

**2 は独立させる。** ここだけが挙動を変えうるので、
問題が出たときに revert する単位が他と混ざっていると切り分けができない。

**3 も独立させる。** コメント削除は 1 と同じファイル群を触るが、
まとめると 1 の差分から「宣言を移しただけか」が読み取れなくなる。
Git の改名検出も、削除量が増えるほど外れやすくなる。

1 は当初 2 つに分けていた（改名 / 分割）。分けなくてよい理由は、
**改名と分割の対象がほぼ重ならない**ため。改名するのは Repository 系 6 ファイル、
分割するのは `Canvas.swift` / `ImageMemoWorkflow.swift` / `CanvasCoding.swift` などで、
両方に当たるのは `MemoWriteMonitoring.swift` と Infrastructure の 3 ファイルだけ。
いずれも削る量が小さく（`enum` 1 個の抽出）、Git の改名検出は効いたままになる。

### 各コミットで通すテスト

```sh
xcodebuild test -scheme qool -destination 'platform=macOS' -only-testing:qoolTests
```

コミット 2 のみ挙動を変えうる。テスト 65 件のうち Canvas 系を触るのは
`CanvasCodingTests` だけで、**編集 UseCase には現状テストがない。**
`CanvasViewModel` はどこからも生成されていない（S5 キャンバス編集ウィンドウが未実装）ため
実行経路もない。**コミット 2 は S5 キャンバス編集ウィンドウの実装前に済ませておく価値が高い。**

## 完成後の構成

```text
qool/
  App/
    QoolApp.swift            AppDelegate.swift
  Presentation/
    Enums/        MemoPersistenceStatus.swift
    ViewModels/   AppRootViewModel.swift          CanvasViewModel.swift
    Views/        MemoPanelView.swift
    Support/      CanvasColor+SwiftUI.swift       RGBAComponents+SwiftUI.swift
  Application/
    UseCases/
      Memo/       LoadMemosUseCase.swift          CreateMemoUseCase.swift
                  SaveMemoUseCase.swift           FlushMemosUseCase.swift
                  ObserveWriteStatesUseCase.swift
      Canvas/     MoveCanvasElementsUseCase.swift DeleteCanvasElementsUseCase.swift
                  UpdateCanvasElementUseCase.swift
                  UpdateCanvasElementsUseCase.swift
                  UnionCanvasElementsUseCase.swift
  Domain/
    Enums/        CanvasElementKind.swift         CanvasTool.swift
                  CanvasColor.swift               MemoWriteState.swift
    Models/       Memo.swift                      Canvas.swift
                  CanvasElement.swift             CanvasElementSnapshot.swift
                  CanvasPathContour.swift         NormalizedPoint.swift
                  RGBAComponents.swift            ImageCutoutDraft.swift
                  ImageAdjustment.swift
    Coding/       RGBAComponents+Codable.swift    CanvasColor+Codable.swift
                  CanvasElement+Codable.swift     CanvasElementSnapshot+Codable.swift
    Repositories/ MemoRepositoryProtocol.swift    MemoWriteMonitoringProtocol.swift
                  ImageAssetRepositoryProtocol.swift
    Services/     CanvasElementFactory.swift      CanvasSelectionService.swift
                  CanvasDraftElementBuilder.swift
  Infrastructure/
    Enums/        MemoWriteFailure.swift
    Persistence/  FileMemoRepositoryInfrastructure.swift
                  InMemoryMemoRepositoryInfrastructure.swift
                  DebouncedMemoRepositoryInfrastructure.swift
```

22 ファイル → 45 ファイル。
[取り込み計画](../image-editing/04-integration-plan.md)で追加される 15 型ほどの置き場所は、
この規約でそのまま決まる（enum は `Domain/Enums/`、抽出器は
`Infrastructure/Vision/~Infrastructure`、輪郭処理は `Domain/Services/`）。
