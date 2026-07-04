import Foundation

/// レキシカルスコープの環境(変数束縛のチェーン)。
final class LispEnvironment {
    private var table: [String: LispValue] = [:]
    let parent: LispEnvironment?

    init(parent: LispEnvironment? = nil) {
        self.parent = parent
    }

    /// この環境に新しい束縛を作る(let / 引数 / defglobal)
    func define(_ name: String, _ value: LispValue) {
        table[name] = value
    }

    func lookup(_ name: String) -> LispValue? {
        var env: LispEnvironment? = self
        while let current = env {
            if let value = current.table[name] {
                return value
            }
            env = current.parent
        }
        return nil
    }

    /// 既存の束縛を書き換える(setq)。見つからなければエラー
    func set(_ name: String, _ value: LispValue) throws {
        var env: LispEnvironment? = self
        while let current = env {
            if current.table[name] != nil {
                current.table[name] = value
                return
            }
            env = current.parent
        }
        throw LispError("未定義の変数です: \(name)")
    }
}
