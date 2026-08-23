# qool ドキュメント

**画像や図形を組み合わせて作る、Mac 上のメモアプリ。**

## 読む順番

| # | ドキュメント | 内容 |
|---|--------------|------|
| 1 | [product/mvp.md](product/mvp.md) | **プロダクト概要と MVP の定義**。何を作ろうとしているか、現状とのギャップ、決定が必要な事項 |
| 2 | [product/hotkeys.md](product/hotkeys.md) | **キーバインド設計**。`⌃Q` プレフィックス方式と実装上の制約 |
| 3 | [design/screens.md](design/screens.md) | **画面リスト**。UI デザインの出発点。原則と 8 画面の定義 |
| 4 | [features/](features/README.md) | **現在の qool の実装**。画面ごとの機能・仕様・制約 |
| 5 | [image-editing/](image-editing/README.md) | **取り込み予定の画像編集機能**。別プロジェクト StarWindow の仕様と移植計画 |
| 6 | [architecture/mvvm-clean-architecture.md](architecture/mvvm-clean-architecture.md) | レイヤ構成と依存方向、現状の逸脱 |
| 7 | [architecture/persistence.md](architecture/persistence.md) | **永続化の設計**。方式比較、画像アセットの持ち方、独自拡張子 `.qool` |
| 8 | [open-questions.md](open-questions.md) | **未確定事項の一覧**。いつ決めればよいか、進行をブロックするか |
| — | [spec.md](spec.md) | 最初期の画面仕様メモ（原典。現在は features/ が詳細版） |

## 全体像

```text
          qool（本プロジェクト / 現在は iOS 実装）
          ├─ メモ一覧
          ├─ キャンバス          ← 図形の作成・編集・Union は実装済み
          ├─ 画像切り抜き ─┐
          └─ 画像調整   ─┴─ モック実装
                              ↑
                              │ ここに入るアルゴリズムと UI
                              │
          StarWindow（検証用 / macOS 実装）
          ├─ なぞり → 7 種の輪郭抽出 → 候補選択
          ├─ 表示範囲エディタ（ブラシ / 投げ縄 / 色域選択 / 白フチ除去）
          ├─ テキスト表示域の指定
          └─ 任意形状のフローティングウィンドウ  ← MVP の「Mac 上で使えるメモ」
```

## 前提

- **qool は macOS 専用アプリとして作り直します**（現在は iOS ターゲット。[理由](product/mvp.md#決定プラットフォーム-macos-専用)）
- **Vision はモダン API**（macOS 15 以降の Swift ネイティブ API）を使います
- **クラッシュアンドビルド**。現在の UI・パラメータは検証段階のもので、作り直す対象です
- 座標は原則として **正規化座標 `0...1`**（qool の `NormalizedPoint` / StarWindow の `CGPoint`）
