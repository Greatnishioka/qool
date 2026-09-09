# qool の開発メモ

macOS 用のメモアプリ。画像を切り抜いてキャンバスに置き、デスクトップへ任意形状のウィンドウとして貼り付ける。

## 前提

**未リリースです。** 保存済みデータとの後方互換は不要です。既存メモが読めなくなる変更をしてよく、互換のためだけのコードは残しません（[#15](https://github.com/Greatnishioka/qool/issues/15)）。

## 構成

[MVVM + Clean Architecture](docs/architecture/mvvm-clean-architecture.md) に沿っています。

```
qool/Domain/          モデル・列挙・純粋な計算（Services）・protocol（Repositories）・独自 Codable（Coding）
qool/Application/     ユースケース。Domain だけに依存する
qool/Infrastructure/  Vision・OpenCV・AppKit・永続化。protocol の実装
qool/Presentation/    ViewModel・View・表示のための持ち回り（Support）
```

**Domain は UI フレームワークを知りません。** `CoreGraphics` までは使いますが、AppKit と SwiftUI は Presentation / Infrastructure に置きます。

## コメントの書き方

このリポジトリのコメントは **「なぜそうしたか」を書きます。** 何をしているかはコードが語るので繰り返しません。特に、**採らなかった選択肢とその理由**を残します。

```swift
/// **輪郭の点を計算し直さず、太い線で膨らませています。**
/// `ContourPadding` で座標を作り直すと、`body` が走るたびに数百点の再計算が入り、
/// ドラッグ中の描画が持ちません。
```

強調（`**`）は、読み飛ばすと壊す箇所に使います。

## ビルドとテスト

```bash
xcodebuild -project qool.xcodeproj -scheme qool -destination 'platform=macOS' build
xcodebuild -project qool.xcodeproj -scheme qool -destination 'platform=macOS' -only-testing:qoolTests test
```

`qoolUITests` は自動化の許可が要るため、CLI からは通らないことがあります。

テストは **Swift Testing**（`@Test` / `#expect` / `#require`）で、**関数名は日本語**です。

## 踏んだ落とし穴

### テスト関数名を数字で始めない

`@Test func 1画素の点が広がる()` のように数字で始めると、構文エラーではなく **ビルドサービスごとクラッシュ**します（`libSwiftDriver` で `EXC_BREAKPOINT`）。原因が表示されないので切り分けに時間がかかります。

### `#expect` の中に複雑な式を書かない

添字計算や絞り込みを直接入れると、マクロの展開が重くなります。値は先に変数へ取り出します。

### `CanvasElement` にプロパティを足したら 3 箇所を直す

合成 `Codable` ではなく **独自の Codable** を持っています。足し忘れると保存されず、しかもビルドは通ります。

1. `qool/Domain/Coding/CanvasElement+Codable.swift`（キー・復号・符号化）
2. `qool/Domain/Models/CanvasElementSnapshot.swift`（結合の構成元）
3. `qool/Application/UseCases/Image/PruneImageAssetsUseCase.swift`（アセットを参照するなら）

実際に `imageSource` で 1 度やらかし、**起動時の掃除で元画像が消える**ところまで行きました。

### `pbxproj` と `Package.resolved` の意図しない変更をコミットしない

Xcode が依存を解決できない状態で開いていると、**OpenCV の依存がプロジェクトから消えた状態で書き戻されます。** コミット前に `git status` を必ず確認します。

DerivedData が古いと同じことが起きます。その場合は該当プロジェクトの DerivedData を消します。

### 性能は最適化を有効にして測る

Debug ビルドは最適化を行わず、配列の境界チェックも残ります。**画素をなめるような処理では Debug と Release で 45 倍違いました**（[#16](https://github.com/Greatnishioka/qool/issues/16)）。Debug の数字で設計を変える判断をしかけたことがあります。

```bash
xcodebuild -project qool.xcodeproj -scheme qool -destination 'platform=macOS' \
  SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule \
  -only-testing:qoolTests/... test
```

`-configuration Release` にすると `@testable import` が使えずテストがビルドできないため、Debug のまま最適化だけ有効にします。

### 座標系

- 輪郭・マスク・正規化座標は **左上原点**
- `CGContext` は **左下原点**。描くときは反転が要ります
- `CGImage` のバッファは 1 行目が上

反転の有無は往復テストでは検出できません（符号化と復号が互いの間違いを打ち消すため）。**片方向のテスト**を置きます。

### CoreGraphics の罠

- **`CGRect.width` は符号を無視して絶対値を返します。** 負の幅を弾きたいなら `size.width` を見ます
- **`CGMutablePath.addLines(between:)` は先頭の点へ自分で move します。** 手前で `move(to:)` してから残りを渡すと、最初の 1 点が落ちます
- **`CGImage` の `alphaOnly` は色空間を持たない指定が要り、Swift の初期化子では作れません。** マスクは明るさで持ち、SwiftUI 側で `luminanceToAlpha()` を使います

## 進行中の設計

**切り抜きの「正」を多角形からグレースケールのラスターマスクへ移しています**（[#12](https://github.com/Greatnishioka/qool/issues/12)）。Photoshop / Krita / GIMP と同じく、ベクターは「入力手段」として残します。

- **フローティングメモの外形は移行に含めません。** 見た目と当たり判定を一致させると、細い線や文字が掴めなくなります
- 余白は輪郭の押し出しではなく **マスクの膨張** で作ります（[#10](https://github.com/Greatnishioka/qool/issues/10) の角ばりの原因が押し出しでした）
- マスクは元画像と同じアセットの保管庫に 1 チャンネルの PNG で置きます

## 作業の進め方

- **コミットは指示があってから。** テストを通した時点で報告し、判断を仰ぎます
- 大きい変更は段階に分け、各段で実機確認できる形にします
- 設計の判断や、直さずに残す不具合は **issue に記録**します
