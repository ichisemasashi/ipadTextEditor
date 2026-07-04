import XCTest
@testable import ichiseEdit

/// マクロマニュアルに載せたコード例が実際に動くことを保証する
final class DocExamplesTest: XCTestCase {
    private func run(_ s: String) throws -> String { try LispInterpreter().run(s).printed() }

    func testBasics() throws {
        XCTAssertEqual(try run("(+ 1 2)"), "3")
        XCTAssertEqual(try run(#"(string-append "あ" "い")"#), "\"あい\"")
        XCTAssertEqual(try run("(let ((x 10) (y 20)) (+ x y))"), "30")
        XCTAssertEqual(try run("(defun double (n) (* n 2)) (double 21)"), "42")
        XCTAssertEqual(try run("(mapcar (lambda (x) (* x x)) '(1 2 3))"), "(1 4 9)")
    }

    func testForLoop() throws {
        // マニュアルの for 例が動くこと
        XCTAssertEqual(try run("""
            (defglobal acc "")
            (for ((i 0 (+ i 1))) ((= i 3))
              (setq acc (string-append acc (format nil "~D" i))))
            acc
            """), "\"012\"")
    }

    func testNumberLinesRecipe() throws {
        // レシピ「行に番号を振る」の中核ロジック
        XCTAssertEqual(try run("""
            (let ((lines (string-split "a\nb\nc" "\n")) (n 0) (out nil))
              (while (consp lines)
                (setq n (+ n 1))
                (setq out (cons (format nil "~D. ~A" n (car lines)) out))
                (setq lines (cdr lines)))
              (string-join (reverse out) "\n"))
            """), "\"1. a\\n2. b\\n3. c\"")
    }

    func testILOSExample() throws {
        XCTAssertEqual(try run("""
            (defclass <person> ()
              ((name :initarg :name :accessor person-name)
               (age  :initform 0 :initarg :age :accessor person-age)))
            (defglobal taro (create (class <person>) :name "太郎" :age 30))
            (defgeneric greet (p))
            (defmethod greet ((p <person>))
              (string-append "こんにちは、" (person-name p) "さん"))
            (greet taro)
            """), "\"こんにちは、太郎さん\"")
    }
}
