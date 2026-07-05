import SwiftUI

/// マクロコマンドに割り当てるキーボードショートカット(外部キーボード用)。
/// "cmd+shift+s" のような文字列から生成する。
struct MacroShortcut: Equatable {
    let key: Character
    let modifiers: EventModifiers

    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(KeyEquivalent(key), modifiers: modifiers)
    }

    /// 例: "cmd+shift+s" / "ctrl+alt+d"。
    /// 修飾キーは cmd(command)/ shift / alt(option, opt)/ ctrl(control)。
    /// 通常入力と衝突しないよう、cmd / ctrl / alt のいずれかを必須とする。
    static func parse(_ spec: String) throws -> MacroShortcut {
        let tokens = spec.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard tokens.count >= 2 else {
            throw LispError(":shortcut は \"cmd+shift+s\" のように修飾キー+1文字で指定してください: \(spec)")
        }

        var modifiers: EventModifiers = []
        for token in tokens.dropLast() {
            switch token {
            case "cmd", "command", "⌘":
                modifiers.insert(.command)
            case "shift", "⇧":
                modifiers.insert(.shift)
            case "alt", "option", "opt", "⌥":
                modifiers.insert(.option)
            case "ctrl", "control", "⌃":
                modifiers.insert(.control)
            default:
                throw LispError(":shortcut: 未知の修飾キーです: \(token)(cmd/shift/alt/ctrl が使えます)")
            }
        }

        let keyToken = tokens[tokens.count - 1]
        guard keyToken.count == 1, let key = keyToken.first else {
            throw LispError(":shortcut: キーは1文字で指定してください: \(spec)")
        }
        guard !modifiers.isDisjoint(with: [.command, .control, .option]) else {
            throw LispError(":shortcut: cmd / ctrl / alt のいずれかの修飾キーが必要です: \(spec)")
        }
        return MacroShortcut(key: key, modifiers: modifiers)
    }
}
