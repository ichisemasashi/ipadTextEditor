import XCTest
@testable import ichiseEdit

final class LispInterpreterTests: XCTestCase {

    /// ソースを評価して最後の値の表示文字列を返す
    private func run(_ source: String) throws -> String {
        try LispInterpreter().run(source).printed()
    }

    // MARK: - リーダ

    func testReaderBasics() throws {
        XCTAssertEqual(try run("42"), "42")
        XCTAssertEqual(try run("-7"), "-7")
        XCTAssertEqual(try run("3.14"), "3.14")
        XCTAssertEqual(try run(#""hello\nworld""#), #""hello\nworld""#)
        XCTAssertEqual(try run("'foo"), "foo")
        XCTAssertEqual(try run("'(1 2 3)"), "(1 2 3)")
        XCTAssertEqual(try run("'(1 . 2)"), "(1 . 2)")
        XCTAssertEqual(try run("#\\a"), "#\\a")
        XCTAssertEqual(try run("#\\newline"), "#\\newline")
        XCTAssertEqual(try run("#(1 2 3)"), "#(1 2 3)")
    }

    func testSymbolsAreCaseInsensitive() throws {
        XCTAssertEqual(try run("(LET ((X 1)) (+ X 2))"), "3")
    }

    func testComments() throws {
        XCTAssertEqual(try run("; コメント\n1 #| ブロック |# 2"), "2")
    }

    // MARK: - 数値・比較

    func testArithmetic() throws {
        XCTAssertEqual(try run("(+ 1 2 3)"), "6")
        XCTAssertEqual(try run("(- 10 3 2)"), "5")
        XCTAssertEqual(try run("(- 5)"), "-5")
        XCTAssertEqual(try run("(* 2 3 4)"), "24")
        XCTAssertEqual(try run("(/ 10 2)"), "5")
        XCTAssertEqual(try run("(/ 7 2)"), "3.5")
        XCTAssertEqual(try run("(mod -7 3)"), "2")
        XCTAssertEqual(try run("(rem -7 3)"), "-1")
        XCTAssertEqual(try run("(+ 1 2.5)"), "3.5")
        XCTAssertEqual(try run("(max 3 1 4 1 5)"), "5")
        XCTAssertEqual(try run("(floor 3.7)"), "3")
        XCTAssertEqual(try run("(round 3.5)"), "4")
    }

    func testComparison() throws {
        XCTAssertEqual(try run("(< 1 2 3)"), "t")
        XCTAssertEqual(try run("(< 1 3 2)"), "nil")
        XCTAssertEqual(try run("(= 2 2.0)"), "t")
        XCTAssertEqual(try run("(>= 3 3 2)"), "t")
    }

    func testDivisionByZero() {
        XCTAssertThrowsError(try run("(/ 1 0)"))
    }

    // MARK: - 束縛・関数

    func testLetAndClosures() throws {
        XCTAssertEqual(try run("(let ((x 1) (y 2)) (+ x y))"), "3")
        XCTAssertEqual(try run("(let* ((x 1) (y (+ x 1))) y)"), "2")
        XCTAssertEqual(try run("""
            (defglobal make-adder (lambda (n) (lambda (x) (+ x n))))
            (funcall (funcall make-adder 10) 5)
            """), "15")
    }

    func testDefunAndRecursion() throws {
        XCTAssertEqual(try run("""
            (defun fib (n)
              (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
            (fib 15)
            """), "610")
    }

    func testRestParameter() throws {
        XCTAssertEqual(try run("(defun f (a &rest rest) (list a rest)) (f 1 2 3)"), "(1 (2 3))")
        XCTAssertEqual(try run("(defun g (a :rest rest) rest) (g 1)"), "nil")
    }

    func testSetqAndDefglobal() throws {
        XCTAssertEqual(try run("(defglobal x 1) (setq x (+ x 10)) x"), "11")
        XCTAssertThrowsError(try run("(setq undefined-var 1)"))
        XCTAssertThrowsError(try run("(defconstant c 1) (setq c 2)"))
    }

    // MARK: - 制御構造

    func testCondCaseAndOr() throws {
        XCTAssertEqual(try run("(cond (nil 1) (t 2))"), "2")
        XCTAssertEqual(try run("(cond ((= 1 2) 'a))"), "nil")
        XCTAssertEqual(try run("(case 2 ((1) 'one) ((2 3) 'two-or-three) (t 'other))"), "two-or-three")
        XCTAssertEqual(try run("(case 9 ((1) 'one) (t 'other))"), "other")
        XCTAssertEqual(try run("(and 1 2 3)"), "3")
        XCTAssertEqual(try run("(and 1 nil 3)"), "nil")
        XCTAssertEqual(try run("(or nil 2 3)"), "2")
        XCTAssertEqual(try run("(or nil nil)"), "nil")
    }

    func testWhileAndFor() throws {
        XCTAssertEqual(try run("""
            (defglobal sum 0)
            (defglobal i 0)
            (while (< i 5)
              (setq sum (+ sum i))
              (setq i (+ i 1)))
            sum
            """), "10")
        XCTAssertEqual(try run("""
            (for ((i 0 (+ i 1))
                  (acc nil (cons i acc)))
                 ((= i 4) acc))
            """), "(3 2 1 0)")
    }

    func testBlockAndCatch() throws {
        XCTAssertEqual(try run("(block done (return-from done 42) 99)"), "42")
        XCTAssertEqual(try run("(catch 'tag (throw 'tag 7) 99)"), "7")
    }

    func testUnwindProtectRunsCleanupOnThrow() throws {
        XCTAssertEqual(try run("""
            (defglobal log nil)
            (catch 'out
              (unwind-protect
                  (progn (setq log (cons 'body log)) (throw 'out 0))
                (setq log (cons 'cleanup log))))
            log
            """), "(cleanup body)")
    }

    // MARK: - マクロ・quasiquote

    func testQuasiquote() throws {
        XCTAssertEqual(try run("(let ((x 5)) `(a ,x ,@(list 1 2)))"), "(a 5 1 2)")
    }

    func testDefmacro() throws {
        XCTAssertEqual(try run("""
            (defmacro my-unless (test then)
              `(if ,test nil ,then))
            (my-unless nil 'ran)
            """), "ran")
        // マクロは引数を評価しない(then 側が評価されないことを確認)
        XCTAssertEqual(try run("""
            (defmacro my-unless (test then)
              `(if ,test nil ,then))
            (defglobal hit nil)
            (my-unless t (setq hit t))
            hit
            """), "nil")
    }

    // MARK: - リスト・文字列

    func testListFunctions() throws {
        XCTAssertEqual(try run("(car '(1 2 3))"), "1")
        XCTAssertEqual(try run("(cdr '(1 2 3))"), "(2 3)")
        XCTAssertEqual(try run("(append '(1 2) '(3) nil)"), "(1 2 3)")
        XCTAssertEqual(try run("(reverse '(1 2 3))"), "(3 2 1)")
        XCTAssertEqual(try run("(length '(a b c))"), "3")
        XCTAssertEqual(try run("(mapcar (lambda (x) (* x x)) '(1 2 3))"), "(1 4 9)")
        XCTAssertEqual(try run("(mapcar #'+ '(1 2) '(10 20))"), "(11 22)")
        XCTAssertEqual(try run("(member 2 '(1 2 3))"), "(2 3)")
        XCTAssertEqual(try run("(assoc 'b '((a . 1) (b . 2)))"), "(b . 2)")
        XCTAssertEqual(try run("(nth 1 '(a b c))"), "b")
        XCTAssertEqual(try run("(elt \"あいう\" 1)"), "#\\い")
    }

    func testStringFunctions() throws {
        XCTAssertEqual(try run(#"(string-append "foo" "bar")"#), "\"foobar\"")
        XCTAssertEqual(try run(#"(substring "こんにちは" 1 3)"#), "\"んに\"")
        XCTAssertEqual(try run(#"(string= "a" "a")"#), "t")
        XCTAssertEqual(try run(#"(string-index "cd" "abcdef")"#), "2")
        XCTAssertEqual(try run(#"(string-index "xx" "abc")"#), "nil")
        XCTAssertEqual(try run("(char-code #\\A)"), "65")
        XCTAssertEqual(try run("(code-char 12354)"), "#\\あ")
        XCTAssertEqual(try run(#"(parse-number "3.5")"#), "3.5")
    }

    func testFormat() throws {
        XCTAssertEqual(
            try run(#"(format nil "~A は ~D 歳~%" "太郎" 20)"#),
            "\"太郎 は 20 歳\\n\""
        )
        let interpreter = LispInterpreter()
        var printed = ""
        interpreter.output = { printed += $0 }
        _ = try interpreter.run(#"(format t "x=~D" 42)"#)
        XCTAssertEqual(printed, "x=42")
    }

    func testConvert() throws {
        XCTAssertEqual(try run("(convert 42 <string>)"), "\"42\"")
        XCTAssertEqual(try run(#"(convert "42" <integer>)"#), "42")
        XCTAssertEqual(try run("(convert 'foo <string>)"), "\"foo\"")
        XCTAssertEqual(try run(#"(convert "ab" <list>)"#), "(#\\a #\\b)")
        XCTAssertEqual(try run("(convert 3 <float>)"), "3.0")
    }

    func testTextUtilities() throws {
        XCTAssertEqual(try run(#"(string-split "a,b,,c" ",")"#), #"("a" "b" "" "c")"#)
        XCTAssertEqual(try run(#"(string-join (list "a" "b" "c") "-")"#), "\"a-b-c\"")
        XCTAssertEqual(try run(#"(sort (list "banana" "apple" "cherry"))"#), #"("apple" "banana" "cherry")"#)
        XCTAssertEqual(try run("(sort (list 3 1 2))"), "(1 2 3)")
    }

    // MARK: - エラー処理

    func testErrorAndWithHandler() throws {
        XCTAssertThrowsError(try run(#"(error "だめ")"#))
        XCTAssertEqual(try run("""
            (with-handler
              (lambda (condition) 'recovered)
              (error "問題発生"))
            """), "recovered")
    }

    // MARK: - ダイナミック変数

    func testDynamicVariables() throws {
        XCTAssertEqual(try run("""
            (defdynamic *level* 1)
            (defun get-level () (dynamic *level*))
            (list (get-level)
                  (dynamic-let ((*level* 2)) (get-level))
                  (get-level))
            """), "(1 2 1)")
    }

    // MARK: - 安全性(タイムアウト・深度制限)

    func testTimeout() {
        let interpreter = LispInterpreter()
        interpreter.timeoutSeconds = 0.05
        XCTAssertThrowsError(try interpreter.run("(while t nil)")) { error in
            XCTAssertTrue("\(error)".contains("タイムアウト"))
        }
    }

    func testDepthLimit() {
        let interpreter = LispInterpreter()
        interpreter.maxDepth = 100
        XCTAssertThrowsError(try interpreter.run("(defun f (n) (f (+ n 1))) (f 0)")) { error in
            XCTAssertTrue("\(error)".contains("再帰"))
        }
    }
}
