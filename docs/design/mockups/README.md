# モックアップ

[画面リスト](../screens.md)を HTML に起こしたものです。
Claude Design プロジェクト「qool — macOS メモアプリ」と同じ内容で、こちらが同期元です。

## 生成物です。直接編集しないでください

すべての `.html` は [build.py](build.py) から生成されます。

```sh
python3 docs/design/mockups/build.py
```

共通 CSS を各ファイルにインライン展開しているため、1 つのトークンを変えると
14 ファイルすべてが書き変わります。**HTML を手で直すと次回の生成で消えます。**

インライン展開しているのは、Claude Design のカード描画で外部 CSS の
相対パス解決が保証されないためです。

## 構成

```text
foundations/   カラー、タイポグラフィ
components/    メモ行、パネルの構成要素、インスペクタ、浮くインスペクタ
screens/       S1〜S8
```

## 注意

CSS の `backdrop-filter` では [Liquid Glass を近似しているだけ](../screens.md#モックアップの限界)です。
レイアウトと情報密度を決めるためのもので、**最終的な見た目の判断には使えません。**
