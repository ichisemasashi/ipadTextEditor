import XCTest
@testable import ichiseEdit

final class LispILOSTests: XCTestCase {

    private func run(_ source: String) throws -> String {
        try LispInterpreter().run(source).printed()
    }

    // MARK: - クラス定義・インスタンス

    func testDefclassAndAccessors() throws {
        let source = """
        (defclass <point> () ((x :initform 0 :initarg :x :accessor point-x)
                              (y :initform 0 :initarg :y :accessor point-y)))
        (defglobal p (create (class <point>) :x 3 :y 4))
        (list (point-x p) (point-y p))
        """
        XCTAssertEqual(try run(source), "(3 4)")
    }

    func testInitformDefault() throws {
        let source = """
        (defclass <counter> () ((n :initform 10 :accessor counter-n)))
        (counter-n (create (class <counter>)))
        """
        XCTAssertEqual(try run(source), "10")
    }

    func testAccessorSetter() throws {
        let source = """
        (defclass <box> () ((v :initform 0 :accessor box-v)))
        (defglobal b (create (class <box>)))
        (set-box-v b 42)
        (box-v b)
        """
        XCTAssertEqual(try run(source), "42")
    }

    func testPredicatesAndClassOf() throws {
        let source = """
        (defclass <animal> () ())
        (defglobal a (create (class <animal>)))
        (list (instancep a) (instancep 5) (class-name (class-of a)))
        """
        XCTAssertEqual(try run(source), "(t nil <animal>)")
    }

    // MARK: - 総称関数・ディスパッチ

    func testGenericDispatchByClass() throws {
        let source = """
        (defclass <dog> () ())
        (defclass <cat> () ())
        (defgeneric speak (a))
        (defmethod speak ((a <dog>)) "ワン")
        (defmethod speak ((a <cat>)) "ニャー")
        (list (speak (create (class <dog>))) (speak (create (class <cat>))))
        """
        XCTAssertEqual(try run(source), "(\"ワン\" \"ニャー\")")
    }

    func testInheritedMethodDispatch() throws {
        // 子クラスは親のメソッドを継承する
        let source = """
        (defclass <animal> () ())
        (defclass <dog> (<animal>) ())
        (defgeneric describe (a))
        (defmethod describe ((a <animal>)) "動物")
        (describe (create (class <dog>)))
        """
        XCTAssertEqual(try run(source), "\"動物\"")
    }

    func testMostSpecificMethodWins() throws {
        let source = """
        (defclass <animal> () ())
        (defclass <dog> (<animal>) ())
        (defgeneric describe (a))
        (defmethod describe ((a <animal>)) "動物")
        (defmethod describe ((a <dog>)) "犬")
        (describe (create (class <dog>)))
        """
        XCTAssertEqual(try run(source), "\"犬\"")
    }

    // MARK: - メソッド結合

    func testBeforeAfterAndCallNextMethod() throws {
        let source = """
        (defclass <animal> () ())
        (defclass <dog> (<animal>) ())
        (defglobal log nil)
        (defgeneric act (a))
        (defmethod act ((a <animal>)) (setq log (cons 'animal-primary log)))
        (defmethod act ((a <dog>))
          (setq log (cons 'dog-primary log))
          (call-next-method))
        (defmethod act :before ((a <dog>)) (setq log (cons 'before log)))
        (defmethod act :after ((a <dog>)) (setq log (cons 'after log)))
        (act (create (class <dog>)))
        (reverse log)
        """
        // before → dog-primary → (call-next-method) animal-primary → after
        XCTAssertEqual(try run(source), "(before dog-primary animal-primary after)")
    }

    func testAroundMethod() throws {
        let source = """
        (defclass <thing> () ())
        (defgeneric wrap (a))
        (defmethod wrap ((a <thing>)) "core")
        (defmethod wrap :around ((a <thing>))
          (string-append "[" (call-next-method) "]"))
        (wrap (create (class <thing>)))
        """
        XCTAssertEqual(try run(source), "\"[core]\"")
    }

    func testNextMethodP() throws {
        let source = """
        (defclass <base> () ())
        (defclass <derived> (<base>) ())
        (defgeneric has-next (a))
        (defmethod has-next ((a <base>)) (next-method-p))
        (defmethod has-next ((a <derived>)) (list (next-method-p) (call-next-method)))
        (has-next (create (class <derived>)))
        """
        // derived: next-method-p=t、call-next-method → base: next-method-p=nil
        XCTAssertEqual(try run(source), "(t nil)")
    }

    // MARK: - 多重継承(C3 線形化)

    func testMultipleInheritanceC3() throws {
        // 菱形継承: D → B, C → A。優先順位は D B C A
        let source = """
        (defclass <a> () ())
        (defclass <b> (<a>) ())
        (defclass <c> (<a>) ())
        (defclass <d> (<b> <c>) ())
        (defgeneric who (x))
        (defmethod who ((x <a>)) "a")
        (defmethod who ((x <b>)) "b")
        (defmethod who ((x <c>)) "c")
        (who (create (class <d>)))
        """
        // D の優先順位は D→B→C→A なので最も特定的な B が選ばれる
        XCTAssertEqual(try run(source), "\"b\"")
    }

    func testMultipleInheritanceSlotMerge() throws {
        let source = """
        (defclass <named> () ((name :initform "?" :initarg :name :accessor name-of)))
        (defclass <aged> () ((age :initform 0 :initarg :age :accessor age-of)))
        (defclass <person> (<named> <aged>) ())
        (defglobal p (create (class <person>) :name "太郎" :age 30))
        (list (name-of p) (age-of p))
        """
        XCTAssertEqual(try run(source), "(\"太郎\" 30)")
    }

    func testSubclassp() throws {
        let source = """
        (defclass <a> () ())
        (defclass <b> (<a>) ())
        (list (subclassp (class <b>) (class <a>))
              (subclassp (class <a>) (class <b>)))
        """
        XCTAssertEqual(try run(source), "(t nil)")
    }

    // MARK: - エラー

    func testNoApplicableMethodErrors() {
        let source = """
        (defclass <a> () ())
        (defclass <b> () ())
        (defgeneric f (x))
        (defmethod f ((x <a>)) 1)
        (f (create (class <b>)))
        """
        XCTAssertThrowsError(try run(source))
    }

    func testUnknownSuperclassErrors() {
        XCTAssertThrowsError(try run("(defclass <x> (<undefined>) ())"))
    }
}
