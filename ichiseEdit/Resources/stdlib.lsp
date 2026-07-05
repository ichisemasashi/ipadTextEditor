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

;; テキスト選択中の編集メニュー「マクロ」とハンマーメニューに表示される
(define-selection-command "大文字にする"
  (lambda (text) (string-upcase text)))

(define-selection-command "「」で囲む"
  (lambda (text) (string-append "「" text "」")))
