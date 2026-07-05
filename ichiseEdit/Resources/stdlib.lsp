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
