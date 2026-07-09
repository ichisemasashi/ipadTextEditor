# App Store スクリーンショット(13インチ iPad・日本語)

サイズ: **2064 × 2752**(iPad Pro 13インチ 縦向き。App Store の 13インチ必須枠)。
ステータスバーは 9:41・Wi-Fi・満充電に統一済み。UI・日付とも日本語。

App Store Connect には番号順にアップロードしてください。キャプション(任意の
文字入れ)を付ける場合の案も添えます。

| # | ファイル | 内容 | キャプション案 |
|---|---|---|---|
| 1 | 13inch-ja-01-editor.png | プレーンテキストの編集(文字数・行数表示) | シンプルに、書くことに集中 |
| 2 | 13inch-ja-02-markdown.png | Markdown のリアルタイム色分け | Markdown もそのまま美しく |
| 3 | 13inch-ja-03-code.png | Swift のシンタックスハイライト+行番号 | 20以上の言語をコード表示 |
| 4 | 13inch-ja-04-macro-menu.png | マクロのコマンドメニュー(grep・正規表現置換ほか) | マクロで自分好みに拡張 |
| 5 | 13inch-ja-05-dark.png | ダークモード(Markdown) | ダークモードにも対応 |

## 予備

- `13inch-ja-05-dark-code-alt.png` は含めていません(scratchpad のみ)。
  ダークモードを「コード表示」で見せたい場合はショット5と差し替え可能です。

## 撮り直しの手順(メモ)

1. iPad Pro 13インチ シミュレータを日本語(システム言語 ja-JP)で起動
2. ステータスバーを統一: `xcrun simctl status_bar <UDID> override --time "9:41" --batteryState discharging --batteryLevel 100 --cellularMode notSupported --wifiBars 3`
3. サンプル(メモ.txt / README.md / Fibonacci.swift)をアプリの Documents に置いて開く
4. ダークは `xcrun simctl ui <UDID> appearance dark` 後、アプリを再起動して撮影
   (ライブ切替だとナビ/ツールバーが明色のまま残るため)
5. `xcrun simctl io <UDID> screenshot out.png` で撮影
