# ichiseEdit マクロ マニュアル

ichiseEdit は **ISLISP** で書いたマクロでエディタを拡張できます。テキストの
一括変換、定型文の挿入、集計、複数ファイルの処理などを自分で自動化できます。

- 対象読者: マクロを書きたいユーザー(ISLISP/Lisp の予備知識は不要)
- 関連文書: 言語仕様・設計は [macro-requirements.md](macro-requirements.md)

---

## 目次

1. [はじめに — 3 分で最初のマクロ](#1-はじめに--3-分で最初のマクロ)
2. [マクロの置き場所と読み込み](#2-マクロの置き場所と読み込み)
3. [ISLISP 文法の基礎](#3-islisp-文法の基礎)
4. [3 種類のマクロ](#4-3-種類のマクロ)
5. [REPL で試す](#5-repl-で試す)
6. [レシピ集(そのまま使える例)](#6-レシピ集そのまま使える例)
7. [関数リファレンス](#7-関数リファレンス)
8. [オブジェクト指向(ILOS)](#8-オブジェクト指向ilos)
9. [安全性と制限](#9-安全性と制限)
10. [困ったときは](#10-困ったときは)

---

## 1. はじめに — 3 分で最初のマクロ

「行末の余分な空白を消す」マクロを作ってみます。

1. 「ファイル」アプリで **この iPad 内 → ichiseEdit → Macros** を開く
2. 新しいテキストファイル `my-macro.lsp` を作る
3. 次を書いて保存する:

```lisp
(define-command "行末の空白を削除"
  (lambda ()
    (re-replace-all "[ \t]+$" "")))
```

4. ichiseEdit で適当な文書を開き、ツールバーの **ハンマー(🔨)メニュー**を開く
5. 一覧に「行末の空白を削除」が出るので、タップすると実行される

うまくいかないときは、ハンマーメニューの「マクロを再読み込み」で読み直せます。
マクロの実行結果は **⌘Z(取り消し)一回で丸ごと元に戻せます**。

> ヒント: `.lsp` ファイルを ichiseEdit で開くと、ISLISP のシンタックス
> ハイライトが効くので書きやすくなります。

---

## 2. マクロの置き場所と読み込み

- 置き場所: **この iPad 内/ichiseEdit/Macros/** の中の `*.lsp` ファイル
- アプリ起動時に Macros フォルダの全 `.lsp` を読み込みます
- 編集後は **ハンマーメニュー → マクロを再読み込み** で即反映
- 初回起動時にサンプルマクロが自動配置されます(手本として読めます)
- 読み込み中にエラーがあると、どのファイルの何行かをアラートで知らせます

1 つの `.lsp` ファイルに複数のコマンドを定義してかまいません。

### 標準コマンドと上書き

「行をソート」「重複行を削除」「日付を挿入」などの標準コマンドは、アプリに
同梱の標準ライブラリ(ISLISP 製)で定義されており、**Macros フォルダの
ファイルを消しても失われません**。

自分のマクロで**同じ名前のコマンドを定義すると、そちらが優先されます**。
標準コマンドの挙動を自分好みに書き換えたいときは、同名で定義し直して
ください(サンプルファイルがその実例になっています)。

---

## 3. ISLISP 文法の基礎

Lisp を知らなくても、以下だけ押さえれば書けます。

### すべては括弧の式

`(関数 引数1 引数2 ...)` の形で「関数を呼ぶ」のが基本です。

```lisp
(+ 1 2)              ; => 3   足し算
(string-append "あ" "い")  ; => "あい"  文字列の連結
(insert "こんにちは")      ; カーソル位置に文字を挿入
```

括弧は入れ子にできます。内側から評価されます。

```lisp
(insert (current-date-string "yyyy-MM-dd"))   ; 今日の日付を挿入
```

### データの種類

| 種類 | 例 |
|---|---|
| 整数 | `42` `-7` |
| 小数 | `3.14` |
| 文字列 | `"こんにちは"`(改行は `\n`、タブは `\t`) |
| シンボル(名前) | `foo` `my-var` |
| 真偽 | 真は `t`、偽と空リストは `nil` |
| リスト | `(1 2 3)` `("a" "b")` |

### 変数と関数

```lisp
(let ((x 10) (y 20))     ; x と y に値を束縛(この範囲だけ有効)
  (+ x y))               ; => 30

(defglobal counter 0)    ; グローバル変数
(setq counter (+ counter 1))  ; 代入

(defun double (n)        ; 関数を定義
  (* n 2))
(double 21)              ; => 42

(lambda (n) (* n 2))     ; 名前のない関数(その場で使う)
```

### 条件分岐と繰り返し

```lisp
(if (> x 0) "正" "非正")            ; if

(cond ((< x 0) "負")                ; 多分岐
      ((= x 0) "ゼロ")
      (t       "正"))

(while (> n 0)                      ; 繰り返し
  (setq n (- n 1)))

(for ((i 0 (+ i 1)))               ; カウンタ付き繰り返し
     ((= i 5))                     ; 終了条件
  (insert (format nil "~D行目\n" i)))
```

### リスト処理(マクロで多用)

```lisp
(car '(1 2 3))          ; => 1     先頭
(cdr '(1 2 3))          ; => (2 3) 先頭以外
(length '(a b c))       ; => 3
(reverse '(1 2 3))      ; => (3 2 1)
(mapcar (lambda (x) (* x x)) '(1 2 3))   ; => (1 4 9)  各要素に適用
```

先頭の `'`(クォート)は「評価せずそのままリストとして扱う」印です。

---

## 4. 3 種類のマクロ

マクロは登録の仕方で 3 通りの使われ方をします。

### 4.1 メニューコマンド — `define-command`

ハンマーメニューに項目を追加します。引数なしの関数を渡します。

```lisp
(define-command "全部大文字に"
  (lambda ()
    (set-buffer-text (string-upcase (buffer-text)))))
```

**キーボードショートカット**(外部キーボード用)も割り当てられます:

```lisp
(define-command "全部大文字に"
  (lambda ()
    (set-buffer-text (string-upcase (buffer-text))))
  :shortcut "cmd+shift+u")
```

- 書式: 修飾キーを `+` でつなぎ、最後に 1 文字のキー
- 修飾キー: `cmd`(command)/ `shift` / `alt`(option)/ `ctrl`(control)。
  **cmd / ctrl / alt のいずれかが必須**です
- メニューにショートカットが表示され、外部キーボードから直接実行できます
- ⌘F(検索)など**アプリ既存のショートカットと重複させないよう注意**して
  ください(重複した場合の動作は保証されません)
- `define-selection-command` でも同じように指定できます

### 4.2 選択範囲クイック適用 — `define-selection-command`

テキストを選択したときの編集メニュー(コピー/ペーストが並ぶメニュー)の
**「マクロ」**サブメニューに出ます。**選択文字列を受け取り、置き換える文字列を
返す**関数を渡します。

```lisp
(define-selection-command "「」で囲む"
  (lambda (text)
    (string-append "「" text "」")))
```

### 4.3 REPL — その場で評価

書きかけのマクロを試すための対話コンソールです([5 章](#5-repl-で試す))。

---

## 5. REPL で試す

ハンマーメニュー → **REPL を開く** でエディタ下部にコンソールが出ます。
式を入力して「実行」すると、その場で評価され結果が表示されます。

```
> (+ 1 2)
=> 3
> (buffer-length)
=> 534
> (insert "テスト")      ; エディタに直接効く
=> nil
```

エディタ API もそのまま使えるので、マクロの一部を試したり、文書の状態を
調べたりするのに便利です。`(format t "...")` の出力も REPL に表示されます。

---

## 6. レシピ集(そのまま使える例)

### 行をソートする

```lisp
(define-command "行をソート"
  (lambda ()
    (set-buffer-text
      (string-join (sort (string-split (buffer-text) "\n")) "\n"))))
```

### 重複行を削除する

```lisp
(define-command "重複行を削除"
  (lambda ()
    (let ((lines (string-split (buffer-text) "\n"))
          (seen nil)
          (result nil))
      (while (consp lines)
        (if (member (car lines) seen)
            nil
            (progn
              (setq seen (cons (car lines) seen))
              (setq result (cons (car lines) result))))
        (setq lines (cdr lines)))
      (set-buffer-text (string-join (reverse result) "\n")))))
```

### 見出しに通し番号を振る(選択範囲)

```lisp
(define-selection-command "行に番号を振る"
  (lambda (text)
    (let ((lines (string-split text "\n"))
          (n 0)
          (out nil))
      (while (consp lines)
        (setq n (+ n 1))
        (setq out (cons (format nil "~D. ~A" n (car lines)) out))
        (setq lines (cdr lines)))
      (string-join (reverse out) "\n"))))
```

### 確認してから全置換する

```lisp
(define-command "タブをスペース2つに(確認あり)"
  (lambda ()
    (if (confirm "タブをスペース2つに置き換えますか?")
        (progn
          (replace-all "\t" "  ")
          (message "置き換えました"))
        (message "キャンセルしました"))))
```

### 日付見出しを挿入する

```lisp
(define-command "日付見出しを挿入"
  (lambda ()
    (insert (format nil "## ~A\n\n" (current-date-string "yyyy-MM-dd")))))
```

### 文書を読み上げて校正する

```lisp
(define-command "読み上げる"
  (lambda () (speak (buffer-text))))
```

---

## 7. 関数リファレンス

`&opt` は省略可能な引数を表します。

### 7.1 エディタ操作(現在の文書)

| 関数 | 説明 |
|---|---|
| `(buffer-text)` | 文書全体を文字列で返す |
| `(set-buffer-text str)` | 文書全体を置き換える |
| `(buffer-substring start end)` | 部分文字列(文字位置。0 始まり) |
| `(buffer-length)` / `(char-count)` | 文字数 |
| `(line-count)` | 行数 |
| `(buffer-name)` | ファイル名 |
| `(point)` | カーソル位置(文字位置) |
| `(goto-char pos)` | カーソルを移動 |
| `(line-start pos)` | pos を含む行の行頭位置 |
| `(line-end pos)` | pos を含む行の行末位置(改行の手前) |
| `(insert str)` | カーソル位置に挿入 |
| `(delete-region start end)` | 範囲を削除 |
| `(selection-start)` / `(selection-end)` | 選択範囲の開始/終了位置 |
| `(set-selection start end)` | 選択範囲を設定 |
| `(selected-text)` | 選択中の文字列(なければ `nil`) |
| `(replace-selection str)` | 選択範囲を置き換える |

位置はすべて **文字単位**(絵文字なども 1 文字)です。

### 7.2 検索・置換

| 関数 | 説明 |
|---|---|
| `(search-forward str &opt from)` | 前方検索。見つかった位置 or `nil` |
| `(replace-all from to)` | 全置換。置換した件数を返す |
| `(re-replace-all pattern template)` | 正規表現で全置換。`^ $` は各行に効く |

### 7.3 ユーティリティ

| 関数 | 説明 |
|---|---|
| `(clipboard-text)` | クリップボードの文字列 |
| `(set-clipboard str)` | クリップボードに書き込む |
| `(current-date-string fmt)` | 日時文字列。`fmt` は `"yyyy-MM-dd"` 等 |
| `(message str)` | 画面下に短時間メッセージを出す |

### 7.4 ダイアログ

| 関数 | 説明 |
|---|---|
| `(alert msg)` | メッセージを表示(OK のみ) |
| `(confirm msg)` | OK/キャンセル。OK なら `t`、キャンセルなら `nil` |
| `(prompt msg &opt default)` | 1 行入力。入力文字列 or `nil` |

### 7.5 ファイル操作

読み書きできるのは **この iPad 内/ichiseEdit** フォルダの中だけです
(相対パスで指定)。フォルダの外へはアクセスできません。

| 関数 | 説明 |
|---|---|
| `(file-read path)` | テキストファイルを読む(UTF-8) |
| `(file-write path str)` | テキストファイルを書く。途中のフォルダは自動作成 |
| `(file-list &opt dir)` | ファイル名の一覧 |
| `(file-exists-p path)` | 存在すれば `t` |

### 7.6 iPadOS 連携

いずれも権限の許可を必要としない機能です。

| 関数 | 説明 |
|---|---|
| `(speak str &opt lang rate)` | 読み上げ。`lang` 例 `"ja-JP"`、`rate` は速度 |
| `(stop-speaking)` | 読み上げを止める |
| `(spell-check text &opt lang)` | スペルミスの語のリストを返す(`lang` 例 `"en"`) |
| `(show-dictionary word)` | 内蔵辞書で語を引く |
| `(share str)` | 共有シートを開く(他アプリへ渡す) |
| `(print-text str)` | AirPrint で印刷 |
| `(open-url str)` | URL を開く(`http(s)` / `mailto` のみ) |
| `(pick-file)` | ファイル選択画面を出し、選ばれたテキストを返す(`nil` でキャンセル) |
| `(export-text filename str)` | 保存先を選んで書き出す |
| `(haptic kind)` | 触覚。`kind` は `success` `warning` `error` `light` |

### 7.7 文字列・リスト・数値(抜粋)

| 関数 | 説明 |
|---|---|
| `(string-append a b ...)` | 連結 |
| `(substring str start end)` | 部分文字列 |
| `(string-split str sep)` | 区切って リストに |
| `(string-join list sep)` | リストを連結して文字列に |
| `(string-upcase str)` / `(string-downcase str)` | 大文字/小文字化 |
| `(string-index needle haystack &opt from)` | 位置 or `nil` |
| `(string= a b)` / `(string< a b)` | 比較 |
| `(sort list)` | 昇順ソート(数値/文字列) |
| `(length x)` `(car x)` `(cdr x)` `(cons a b)` `(list ...)` | リスト基本 |
| `(append ...)` `(reverse x)` `(nth i x)` `(elt x i)` | リスト操作 |
| `(member item list)` `(assoc key alist)` | 探索 |
| `(mapcar fn list...)` `(mapc fn list)` | 各要素に適用 |
| `(+ - * / mod rem abs min max floor ceiling round)` | 数値 |
| `(= /= < > <= >=)` | 数値比較 |
| `(parse-number str)` | 文字列 → 数値 |
| `(format dest template args...)` | 書式化。`dest` が `nil` で文字列を返す |

`format` の書式指定: `~A`(値)`~S`(引用付き)`~D`(整数)`~%`(改行)`~~`(`~`)。

### 7.8 標準ライブラリの関数

アプリに同梱の標準ライブラリ(stdlib.lsp)は **ISLISP で書かれており**、
自分のマクロからそのまま呼べます。エディタの Markdown メニューも
実はこれらの関数で動いています。

| 関数 | 説明 |
|---|---|
| `(wrap-selection prefix suffix placeholder)` | 選択範囲を prefix/suffix で囲む。選択がなければ placeholder を挿入して選択状態にする |
| `(insert-at-line-start str)` | 現在行の行頭に文字列を挿入(カーソル位置は維持) |
| `(md-heading)` `(md-bold)` `(md-italic)` `(md-code)` `(md-link)` | Markdown 記法の挿入コマンド |

```lisp
;; 例: 選択範囲を〜〜で囲む取り消し線コマンドを自作
(define-command "取り消し線"
  (lambda () (wrap-selection "~~" "~~" "text")))
```

### 7.9 述語・制御・定義(抜粋)

- 述語: `null not consp listp symbolp stringp numberp integerp characterp functionp eq eql equal`
- 制御: `if cond case and or progn while for block return-from catch throw unwind-protect with-handler`
- 定義: `defun defmacro defglobal defconstant lambda let let* setq`
- 準クォート: `` ` ``(quasiquote)`,`(unquote)`,@`(unquote-splicing)
- エラー: `(error "メッセージ")` で発生、`with-handler` で捕捉

---

## 8. オブジェクト指向(ILOS)

複雑なマクロはクラスで構造化できます(ISLISP のオブジェクトシステム)。

```lisp
;; クラス定義(多重継承も可)
(defclass <person> ()
  ((name :initarg :name :accessor person-name)
   (age  :initform 0 :initarg :age :accessor person-age)))

;; インスタンス生成
(defglobal taro (create (class <person>) :name "太郎" :age 30))

(person-name taro)          ; => "太郎"
(set-person-age taro 31)    ; アクセサで書き換え

;; 総称関数とメソッド(第1引数のクラスで振り分け)
(defgeneric greet (p))
(defmethod greet ((p <person>))
  (string-append "こんにちは、" (person-name p) "さん"))
(greet taro)                ; => "こんにちは、太郎さん"
```

- スロットオプション: `:initform`(初期値)`:initarg`(生成時のキーワード)
  `:accessor`(読み書き。`set-` 付きで書き込み)`:reader`(読み取り専用)
- メソッド修飾子: `:before` `:after` `:around` と `call-next-method` /
  `next-method-p`
- 多重継承の優先順位は C3 線形化で決まります
- 述語など: `(instancep x)` `(class-of x)` `(class-name cls)`
  `(subclassp a b)` `(generic-function-p x)` `(slot-value obj 'name)`

---

## 9. 安全性と制限

- **取り消し**: マクロ 1 回の実行はまとめて 1 つの取り消し単位です。⌘Z で
  元に戻せます
- **タイムアウト**: 1 回の実行は約 5 秒まで。無限ループは自動で中断されます
  (ダイアログやピッカーで待っている時間は数えません)
- **多重実行の防止**: マクロ実行中は他のマクロを開始できません
- **ネットワーク不可**: 通信する API はありません(App Store の方針)
- **ファイルはサンドボックス内のみ**: ichiseEdit フォルダの外は
  `pick-file` / `export-text`(ユーザーが選ぶ)を除いて触れません
- マクロがエラーを起こしても、エディタ本体や文書は保護されます

---

## 10. 困ったときは

| 症状 | 対処 |
|---|---|
| メニューに出ない | ハンマーメニュー →「マクロを再読み込み」。それでも出なければ `.lsp` の読み込みエラー(アラート)を確認 |
| 「未定義の変数です」 | 関数名・変数名のスペル、または定義前に使っていないか確認 |
| 「引数の数が違います」 | 関数に渡す引数の個数を確認 |
| 「実行がタイムアウトしました」 | `while` の終了条件など無限ループを確認 |
| 括弧のエラー | 開き括弧と閉じ括弧の数が合っているか。`.lsp` を ichiseEdit で開くとハイライトで気づきやすい |
| 変換が意図とずれる | まず REPL で小さく試す。`(buffer-text)` で現在値を確認 |

**REPL は最良のデバッグ手段です。** 大きなマクロを書く前に、部品を REPL で
1 つずつ確かめると確実です。
