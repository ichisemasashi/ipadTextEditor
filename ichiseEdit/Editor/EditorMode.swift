import Foundation

/// 文書の編集モード。ファイルの拡張子から決まる。
enum EditorMode: Equatable {
    case plainText
    case markdown
    case code(LanguageDefinition)

    static func mode(for fileURL: URL?) -> EditorMode {
        let ext = fileURL?.pathExtension.lowercased() ?? ""
        if ["md", "markdown"].contains(ext) {
            return .markdown
        }
        if let language = LanguageRegistry.language(forExtension: ext) {
            return .code(language)
        }
        return .plainText
    }

    var isMarkdown: Bool {
        self == .markdown
    }

    var codeLanguage: LanguageDefinition? {
        if case .code(let language) = self { return language }
        return nil
    }
}

/// 「文法」メニューでの手動選択肢。拡張子に関わらずハイライトを切り替えられる。
enum SyntaxChoice: Hashable, Identifiable {
    case plainText
    case markdown
    case code(String)   // 言語名

    var id: String {
        switch self {
        case .plainText: return "plain"
        case .markdown: return "markdown"
        case .code(let name): return "code:\(name)"
        }
    }

    var displayName: String {
        switch self {
        case .plainText: return String(localized: "Plain Text")
        case .markdown: return "Markdown"
        case .code(let name): return name
        }
    }

    var mode: EditorMode {
        switch self {
        case .plainText: return .plainText
        case .markdown: return .markdown
        case .code(let name):
            if let language = LanguageRegistry.allLanguages.first(where: { $0.name == name }) {
                return .code(language)
            }
            return .plainText
        }
    }

    /// 現在のモードに対応する選択肢(メニューのチェック表示用)
    static func current(_ mode: EditorMode) -> SyntaxChoice {
        switch mode {
        case .plainText: return .plainText
        case .markdown: return .markdown
        case .code(let language): return .code(language.name)
        }
    }
}
