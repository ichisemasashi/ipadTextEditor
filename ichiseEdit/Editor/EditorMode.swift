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
