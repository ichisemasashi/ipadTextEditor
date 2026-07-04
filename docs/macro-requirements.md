# ichiseEdit マクロ機能(ISLISP)要件定義書

- 作成日: 2026-07-04
- ステータス: 確定(v1)
- 親文書: [requirements.md](requirements.md)

## 1. 概要・目的

エディタの機能拡張のためのマクロ言語として ISLISP(ISO/IEC 13816)のサブセットを
アプリに組み込む。ユーザーは ISLISP でマクロ(テキスト変換・定型処理・複数ファイル
処理など)を書き、エディタ内から実行できる。

**この機能を v1.0 に含めてから App Store に提出する**(2026-07-04 決定)。

## 2. 基本方針(確定事項)

| 項目 | 決定内容 |
|---|---|
| マクロ言語 | ISLISP のサブセット |
| インタプリタ | Swift による自前実装(外部依存なし) |
| API 範囲 | 単一文書のテキスト操作+ユーティリティ+複数ファイル操作+限定的な UI 拡張 |
| 実行 UI | ①マクロメニュー ②REPL コンソール ③選択範囲へのクイック適用(3 方式すべて) |
| マクロの保存場所 | 「この iPad 内/ichiseEdit/Macros/」の `.lsp` ファイル |
| リリース | マクロ実装完了後に v1.0 を提出 |

## 3. App Store 適合性(前提制約)

- ガイドライン上、**組み込みインタプリタでユーザー自身が作成したスクリプトを
  実行することは許容される**(Pythonista / Scriptable 等の前例)
- **禁止事項**: ネットワーク経由でコードを取得して実行すること。
  → マクロのダウンロード機能・共有ストアは実装しない(スコープ外)
- マクロができることはアプリ自身の機能(テキスト編集・アプリ内ファイル操作)を
  超えない。OS の権限に影響する操作は提供しない
- 審査提出時のレビューノートに「スクリプトはユーザー作成のみ・サンドボックス内実行・
  ダウンロード実行なし」を明記する

## 4. 言語仕様(ISLISP サブセット)

ISO/IEC 13816 のうち、エディタマクロに必要な範囲を実装する。

### 4.1 データ型

整数 / 浮動小数点数 / 文字列 / シンボル / 文字 / コンスセル(リスト)/
汎用ベクタ / `t` / `nil`

### 4.2 特殊形式・定義形式

- 定義: `defun` `defmacro` `defglobal` `defconstant` `defdynamic`
- 束縛: `let` `let*` `lambda` `setq` `dynamic-let`
- 制御: `if` `cond` `case` `and` `or` `progn` `while` `for`
  `block` `return-from` `catch` `throw` `tagbody`(必要なら) `unwind-protect`
- クォート: `quote` `quasiquote`(`` ` ``)`unquote`(`,`)`unquote-splicing`(`,@`)

### 4.3 組み込み関数(主要なもの)

- 数値: `+ - * / mod rem abs min max floor ceiling round = /= < > <= >=`
- 述語: `null consp listp symbolp stringp numberp integerp characterp functionp eq eql equal`
- リスト: `car cdr cons list append reverse length mapcar mapc member assoc nth elt`
- 文字列: `string-append substring string= string< string-index char-code code-char
  parse-number format`(文字列生成は `format nil` 相当を提供)
- 関数適用: `apply funcall`
- 変換: `convert`(数値⇔文字列⇔シンボル等の主要な組)
- エラー: `error`(発生)+ `with-handler` の簡易版(捕捉)

### 4.4 v1 では実装しないもの

- ILOS(`defclass` / `defgeneric` などのオブジェクトシステム)
- 完全なコンディションシステム(簡易版のみ)
- ストリーム全般(入出力は REPL コンソールとエディタ API 経由のみ)
- パッケージ/モジュール機構
- 末尾呼び出し最適化(実装は単純な再帰。深い再帰は制限で保護)

## 5. エディタ API

マクロから呼べる組み込み関数として提供する。

### 5.1 バッファ(現在の文書)

| 関数 | 機能 |
|---|---|
| `(buffer-text)` | 全文を文字列で返す |
| `(set-buffer-text str)` | 全文を置き換える |
| `(buffer-substring start end)` | 部分文字列(文字オフセット) |
| `(buffer-length)` | 文字数 |
| `(point)` / `(goto-char pos)` | カーソル位置の取得/移動 |
| `(insert str)` | カーソル位置に挿入 |
| `(delete-region start end)` | 範囲削除 |
| `(selection-start)` / `(selection-end)` | 選択範囲 |
| `(set-selection start end)` | 選択範囲の設定 |
| `(selected-text)` | 選択中の文字列(なければ nil) |
| `(replace-selection str)` | 選択範囲を置き換え |
| `(buffer-name)` | ファイル名 |
| `(line-count)` / `(char-count)` | 行数・文字数 |

### 5.2 検索・置換

| 関数 | 機能 |
|---|---|
| `(search-forward str &opt from)` | 前方検索(見つかった位置 or nil) |
| `(replace-all from to)` | 全置換(置換件数を返す) |
| `(re-replace-all pattern template)` | 正規表現による全置換 |

### 5.3 ユーティリティ

| 関数 | 機能 |
|---|---|
| `(clipboard-text)` / `(set-clipboard str)` | クリップボード読み書き |
| `(current-date-string fmt)` | 日時文字列(書式指定可) |
| `(message str)` | 画面下部に短時間表示(トースト) |

### 5.4 複数ファイル操作(サンドボックス内)

**アクセス範囲は「この iPad 内/ichiseEdit」フォルダ配下のみ**(iOS のサンドボックス
制約により、ユーザーが明示的に開いていない任意の場所へはアクセス不能・しない)。
パスは同フォルダからの相対パスで指定する。

| 関数 | 機能 |
|---|---|
| `(file-read path)` | テキストファイルを読む(UTF-8) |
| `(file-write path str)` | テキストファイルを書く(UTF-8) |
| `(file-list dir)` | ファイル一覧(リスト) |
| `(file-exists-p path)` | 存在確認 |

### 5.5 UI 拡張(限定的)

| 関数 | 機能 |
|---|---|
| `(alert msg)` | メッセージダイアログ |
| `(confirm msg)` | OK/キャンセル(t / nil を返す) |
| `(prompt msg &opt default)` | 1 行入力ダイアログ(文字列 or nil) |
| `(define-command name fn)` | マクロメニューにコマンドを登録 |
| `(define-selection-command name fn)` | 選択範囲クイック適用に登録。fn は選択文字列を受け取り置換文字列を返す |

独自パネル・ビューの構築(UI DSL)は v1 では提供しない(将来検討)。

### 5.6 iPadOS 連携

エディタと相性がよく、**権限ダイアログ不要で審査リスクの低い** OS 機能を
マクロから利用できるようにする。

**文章支援(テキスト処理系)**

| 関数 | 機能 | 利用する OS 機能 |
|---|---|---|
| `(speak str &opt lang rate)` | テキストを読み上げる(校正に有用) | AVSpeechSynthesizer |
| `(stop-speaking)` | 読み上げを停止 | 〃 |
| `(spell-check text &opt lang)` | スペルミスの語のリストを返す | UITextChecker |
| `(show-dictionary word)` | 内蔵辞書で語を引く(パネル表示) | UIReferenceLibraryViewController |

**共有・出力**

| 関数 | 機能 | 利用する OS 機能 |
|---|---|---|
| `(share str)` | 共有シートを表示(他アプリへ渡す) | UIActivityViewController |
| `(print-text str)` | AirPrint で印刷 | UIPrintInteractionController |
| `(open-url str)` | URL を既定アプリで開く(例: 選択語の Web 検索) | UIApplication.open |

**ファイル連携(ユーザー選択によるサンドボックス外アクセス)**

| 関数 | 機能 | 利用する OS 機能 |
|---|---|---|
| `(pick-file)` | ファイル選択画面をユーザーに提示し、選ばれたテキストファイルの内容を返す(キャンセルで nil)。**ユーザーが明示的に選ぶため、§5.4 の範囲外のファイルも安全に読める** | UIDocumentPickerViewController |
| `(export-text filename str)` | 保存先をユーザーが選んでテキストを書き出す | 〃(exporting) |

**その他**

| 関数 | 機能 | 利用する OS 機能 |
|---|---|---|
| `(haptic kind)` | 触覚フィードバック(`success` / `warning` / `error` / `light`) | UIFeedbackGenerator |

**調査のうえ M5 で判断する項目**(実現性・審査面の検証が必要)

- `(open-in-new-window path)` — 文書を新規ウィンドウ(別シーン)で開く
- 登録済みマクロコマンドをショートカット App のアクションとして公開(App Intents)。
  実現すれば「ショートカット→マクロ実行」の自動化が可能になるが、実装規模が大きい

**採用しない OS 機能**(エディタに不釣り合いな権限要求・プライバシーリスクのため)

- カメラ・写真ライブラリ、位置情報、連絡先、カレンダー/リマインダー、
  マイク(音声認識)、通知、Bluetooth 等 — 権限ダイアログを伴うデバイス機能は
  マクロ API として提供しない

## 6. 実行環境・安全性

- **タイムアウト**: 1 回の実行は 5 秒まで(超過で中断しエラー表示)。無限ループ保護
- **再帰深度制限**: 例: 10,000(超過でエラー)
- **ネットワークアクセス API なし**
- **ファイルアクセスは §5.4 の範囲のみ**(例外: §5.6 の `pick-file` / `export-text` は
  ユーザーがその場でファイルを明示選択するため安全)
- **iPadOS 連携 API(§5.6)は権限ダイアログ不要の機能に限定**(プライバシー関連の
  Info.plist 利用目的文字列を一切追加しない構成を保つ)
- マクロによる文書変更は **1 回の実行 = 1 つの Undo 単位**(⌘Z で丸ごと戻せる)
- エラーはメッセージ+発生箇所(可能なら式)を REPL / アラートに表示。
  エディタ本体はマクロの失敗から保護される

## 7. マクロの管理・読み込み

- 置き場所: `この iPad 内/ichiseEdit/Macros/*.lsp`(ファイル App から直接編集可能。
  アプリ内で開けば ISLISP ハイライトが効く=実装済み機能を活用)
- アプリ起動時に全 `.lsp` を読み込み、`define-command` / `define-selection-command`
  された項目をメニューに登録する
- マクロメニューに「マクロを再読み込み」を用意(編集後すぐ反映)
- **サンプルマクロを同梱**し、初回起動時に Macros フォルダへコピーする:
  行のソート / 重複行の削除 / 日付挿入 / 選択範囲の大文字化 など 4〜6 本
  (実用+書き方の手本を兼ねる)

## 8. UI 設計

- ツールバーに「マクロ」メニュー(ハンマーアイコン等):
  登録コマンド一覧 / REPL を開く / マクロを再読み込み
- **REPL コンソール**: エディタ下部のパネル。入力欄+評価結果の履歴表示。
  `(insert "hello")` のようにその場でエディタ操作を試せる
- **選択範囲クイック適用**: テキスト選択中の編集メニュー(ペースト等が並ぶメニュー)
  に selection-command を表示し、タップで選択範囲を変換

## 9. 非機能要件

- インタプリタ初期化はアプリ起動を体感で遅らせない(目標 <100ms)
- 数千行の文書に対する通常マクロ(全置換等)が 1 秒以内
- インタプリタはユニットテストで言語仕様を網羅的に検証する(評価器・マクロ展開・
  エラー処理・タイムアウト)

## 10. 実装フェーズ(マクロ機能内)

| フェーズ | 内容 |
|---|---|
| M1 | インタプリタコア(リーダ・評価器・組み込み関数・エラー処理・タイムアウト)+テスト |
| M2 | エディタ API(単一文書)+ Macros フォルダ読込+マクロメニュー |
| M3 | REPL コンソール+選択範囲クイック適用+ユーティリティ API+サンプルマクロ |
| M4 | 複数ファイル API + UI API(ダイアログ) |
| M5 | iPadOS 連携 API(読み上げ・辞書・スペルチェック・共有・印刷・ピッカー等)+仕上げ・ドキュメント。「調査のうえ判断する項目」(§5.6)の採否もここで決定 |

M5 完了後に App Store 提出準備(メタデータ更新を含む)へ進む。

## 11. リスクと対応

| リスク | 対応 |
|---|---|
| 審査リジェクト(2.5.2/3.3.2) | ユーザー作成スクリプトのみ・DL 実行なしをレビューノートで明示。前例(Pythonista 等)あり |
| 無限ループ・暴走 | タイムアウト+再帰制限+実行中の中断 |
| インタプリタの複雑化 | ISLISP サブセットに限定。ILOS 等は実装しない |
| 提出時期の遅れ | フェーズ M1〜M4 で区切り、各フェーズを PR 単位で完結させる |

## 12. スコープ外

- マクロのダウンロード・共有ストア(審査ガイドライン抵触のため恒久的に対象外)
- ILOS(クラスシステム)、パッケージ機構
- ネットワーク API
- アプリのサンドボックス外・任意フォルダへの**ユーザー選択を介さない**ファイルアクセス
  (ユーザーがピッカーで選ぶ `pick-file` / `export-text` は対象内 → §5.6)
- 権限ダイアログを伴うデバイス機能(カメラ・写真・位置情報・連絡先・カレンダー・
  マイク・通知・Bluetooth 等)
- 独自 UI パネルの構築 DSL(将来検討)
- 外部キーボードショートカットへのマクロ割当(将来検討)
