;;; ichiseEdit 標準ライブラリ
;;;
;;; エディタの標準機能のうち、ISLISP で実装されている部分です。
;;; ユーザーマクロ(Macros フォルダ)より先に読み込まれるため、
;;; ここで定義された関数はすべてのマクロから利用できます。

;; ------------------------------------------------------------
;; 選択範囲の編集
;; ------------------------------------------------------------

;; 選択範囲を prefix と suffix で囲む。
;; 選択がなければ placeholder を挿入し、すぐ書き換えられるよう選択状態にする。
(defun wrap-selection (prefix suffix placeholder)
  (let* ((sel (selected-text))
         (start (selection-start))
         (core (if sel sel placeholder)))
    (if sel
        (replace-selection (string-append prefix core suffix))
        (insert (string-append prefix core suffix)))
    (set-selection (+ start (length prefix))
                   (+ start (length prefix) (length core)))
    nil))

;; 現在行の行頭に文字列を挿入する(カーソルの相対位置は維持する)
(defun insert-at-line-start (str)
  (let ((caret (point)))
    (goto-char (line-start caret))
    (insert str)
    (goto-char (+ caret (length str)))
    nil))

;; ------------------------------------------------------------
;; Markdown 編集コマンド(Markdown メニューから呼ばれる)
;; ------------------------------------------------------------

(defun md-heading ()
  (insert-at-line-start "# "))

(defun md-bold ()
  (wrap-selection "**" "**" "text"))

(defun md-italic ()
  (wrap-selection "*" "*" "text"))

(defun md-code ()
  (wrap-selection "`" "`" "code"))

(defun md-link ()
  (wrap-selection "[" "](url)" "title"))

;; ------------------------------------------------------------
;; grep(固定文字列の行検索)
;; ------------------------------------------------------------

;; text の中から query を含む行を ((行番号 . 行) ...) のリストで返す
(defun grep-lines (text query)
  (let ((lines (string-split text "\n"))
        (n 0)
        (result nil))
    (while (consp lines)
      (setq n (+ n 1))
      (if (string-index query (car lines))
          (setq result (cons (cons n (car lines)) result))
          nil)
      (setq lines (cdr lines)))
    (reverse result)))

;; 現在の文書から query を検索し、ヒット行を REPL に出力する。件数を返す
(defun grep-buffer (query)
  (let ((hits (grep-lines (buffer-text) query)))
    (format t "── grep ~S(~A)──~%" query (buffer-name))
    (mapc (lambda (hit)
            (format t "~D: ~A~%" (car hit) (cdr hit)))
          hits)
    (length hits)))

;; 1 ファイルから query を検索して REPL に出力する。件数を返す。
;; 読めないファイル(バイナリ等)は黙ってスキップする
(defun grep-file (query path)
  (with-handler
    (lambda (condition) 0)
    (let ((hits (grep-lines (file-read path) query)))
      (mapc (lambda (hit)
              (format t "~A:~D: ~A~%" path (car hit) (cdr hit)))
            hits)
      (length hits))))

;; dir 配下を再帰的に grep する。dir が "" ならファイルフォルダ全体。件数を返す
(defun grep-directory (query dir)
  (let ((total 0))
    (mapc
      (lambda (name)
        (let ((path (if (string= dir "") name (string-append dir "/" name))))
          (if (file-directory-p path)
              (setq total (+ total (grep-directory query path)))
              (setq total (+ total (grep-file query path))))))
      (file-list dir))
    total))

;; ------------------------------------------------------------
;; 標準コマンド(ハンマーメニューに常に表示される)
;;
;; Macros フォルダのユーザーマクロで同じ名前のコマンドを定義すると、
;; そちらが優先される(標準コマンドを自分の実装で上書きできる)。
;; ------------------------------------------------------------

(define-command "行をソート"
  (lambda ()
    (set-buffer-text
      (string-join (sort (string-split (buffer-text) "\n")) "\n"))))

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

(define-command "行末の空白を削除"
  (lambda ()
    (re-replace-all "[ \t]+$" "")))

(define-command "日付を挿入"
  (lambda ()
    (insert (current-date-string "yyyy-MM-dd"))))

(define-command "読み上げる"
  (lambda () (speak (buffer-text))))

(define-command "読み上げを止める"
  (lambda () (stop-speaking)))

(define-command "共有する"
  (lambda () (share (buffer-text))))

(define-command "grep(このファイル)"
  (lambda ()
    (let ((query (prompt "検索する文字列" "")))
      (if (and query (not (string= query "")))
          (message (format nil "~D件見つかりました(REPLに表示)"
                           (grep-buffer query)))
          nil))))

(define-command "grep(フォルダ再帰)"
  (lambda ()
    (let ((query (prompt "検索する文字列" "")))
      (if (and query (not (string= query "")))
          (let ((dir (prompt "フォルダ(空欄で全体)" "")))
            (if dir
                (progn
                  (format t "── grep ~S(~A 配下)──~%"
                          query (if (string= dir "") "ichiseEdit" dir))
                  (message (format nil "~D件見つかりました(REPLに表示)"
                                   (grep-directory query dir))))
                nil))
          nil))))

;; テキスト選択中の編集メニュー「マクロ」とハンマーメニューに表示される
(define-selection-command "大文字にする"
  (lambda (text) (string-upcase text)))

(define-selection-command "「」で囲む"
  (lambda (text) (string-append "「" text "」")))
