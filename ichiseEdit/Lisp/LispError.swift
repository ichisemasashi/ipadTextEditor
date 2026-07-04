import Foundation

/// マクロ実行時のエラー(ユーザーに表示する)
struct LispError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }

    init(_ message: String) {
        self.message = message
    }
}

/// (throw tag value) の制御フロー
struct LispThrowSignal: Error {
    let tag: LispValue
    let value: LispValue
}

/// (return-from name value) の制御フロー
struct LispBlockReturn: Error {
    let name: String
    let value: LispValue
}
