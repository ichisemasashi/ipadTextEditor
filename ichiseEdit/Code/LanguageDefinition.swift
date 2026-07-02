import Foundation

/// コードハイライト用の言語定義。汎用レキサ(CodeHighlighter)への設定を与える。
struct LanguageDefinition: Equatable {
    let name: String
    let lineComment: String?
    let blockCommentStart: String?
    let blockCommentEnd: String?
    /// 複数行文字列の区切り(例: Python の """)。通常の区切りより先に判定する
    let multilineStringDelimiters: [String]
    let stringDelimiters: [Character]
    let keywords: Set<String>
    let caseInsensitiveKeywords: Bool
    /// 行末が ":" のとき自動インデントを 1 段深くする(Python など)
    let indentsAfterColon: Bool

    init(
        name: String,
        lineComment: String? = nil,
        blockComment: (String, String)? = nil,
        multilineStringDelimiters: [String] = [],
        stringDelimiters: [Character] = ["\""],
        keywords: Set<String> = [],
        caseInsensitiveKeywords: Bool = false,
        indentsAfterColon: Bool = false
    ) {
        self.name = name
        self.lineComment = lineComment
        self.blockCommentStart = blockComment?.0
        self.blockCommentEnd = blockComment?.1
        self.multilineStringDelimiters = multilineStringDelimiters
        self.stringDelimiters = stringDelimiters
        self.keywords = keywords
        self.caseInsensitiveKeywords = caseInsensitiveKeywords
        self.indentsAfterColon = indentsAfterColon
    }

    static func == (lhs: LanguageDefinition, rhs: LanguageDefinition) -> Bool {
        lhs.name == rhs.name
    }
}

/// 拡張子 → 言語定義の対応表。
enum LanguageRegistry {

    static func language(forExtension ext: String) -> LanguageDefinition? {
        byExtension[ext.lowercased()]
    }

    private static let cKeywords: Set<String> = [
        "auto", "break", "case", "char", "const", "continue", "default", "do", "double",
        "else", "enum", "extern", "float", "for", "goto", "if", "int", "long", "register",
        "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef",
        "union", "unsigned", "void", "volatile", "while", "bool", "true", "false", "NULL",
        "nullptr", "class", "namespace", "new", "delete", "public", "private", "protected",
        "template", "this", "throw", "try", "catch", "using", "virtual", "override",
    ]

    private static let jsKeywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
        "default", "delete", "do", "else", "export", "extends", "finally", "for", "function",
        "if", "import", "in", "instanceof", "let", "new", "null", "of", "return", "static",
        "super", "switch", "this", "throw", "true", "false", "try", "typeof", "undefined",
        "var", "void", "while", "with", "yield",
        // TypeScript
        "any", "as", "enum", "implements", "interface", "namespace", "number", "private",
        "protected", "public", "readonly", "string", "type", "boolean", "declare",
    ]

    private static let swift = LanguageDefinition(
        name: "Swift",
        lineComment: "//",
        blockComment: ("/*", "*/"),
        multilineStringDelimiters: ["\"\"\""],
        stringDelimiters: ["\""],
        keywords: [
            "actor", "as", "associatedtype", "async", "await", "break", "case", "catch",
            "class", "continue", "default", "defer", "deinit", "do", "else", "enum",
            "extension", "fallthrough", "false", "fileprivate", "final", "for", "func",
            "guard", "if", "import", "in", "indirect", "init", "inout", "internal", "is",
            "lazy", "let", "mutating", "nil", "nonisolated", "open", "operator", "override",
            "private", "protocol", "public", "repeat", "required", "rethrows", "return",
            "self", "Self", "some", "static", "struct", "subscript", "super", "switch",
            "throw", "throws", "true", "try", "typealias", "var", "weak", "where", "while",
        ]
    )

    private static let python = LanguageDefinition(
        name: "Python",
        lineComment: "#",
        multilineStringDelimiters: ["\"\"\"", "'''"],
        stringDelimiters: ["\"", "'"],
        keywords: [
            "and", "as", "assert", "async", "await", "break", "class", "continue", "def",
            "del", "elif", "else", "except", "finally", "for", "from", "global", "if",
            "import", "in", "is", "lambda", "match", "None", "nonlocal", "not", "or",
            "pass", "raise", "return", "self", "True", "False", "try", "while", "with", "yield",
        ],
        indentsAfterColon: true
    )

    private static let javascript = LanguageDefinition(
        name: "JavaScript",
        lineComment: "//",
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'", "`"],
        keywords: jsKeywords
    )

    private static let json = LanguageDefinition(
        name: "JSON",
        stringDelimiters: ["\""],
        keywords: ["true", "false", "null"]
    )

    private static let yaml = LanguageDefinition(
        name: "YAML",
        lineComment: "#",
        stringDelimiters: ["\"", "'"],
        keywords: ["true", "false", "null", "yes", "no", "on", "off"],
        caseInsensitiveKeywords: true,
        indentsAfterColon: true
    )

    private static let shell = LanguageDefinition(
        name: "Shell",
        lineComment: "#",
        stringDelimiters: ["\"", "'"],
        keywords: [
            "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
            "case", "esac", "function", "in", "return", "exit", "local", "export",
            "readonly", "shift", "break", "continue", "true", "false", "echo", "source",
        ]
    )

    private static let c = LanguageDefinition(
        name: "C / C++ / Objective-C",
        lineComment: "//",
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'"],
        keywords: cKeywords
    )

    private static let java = LanguageDefinition(
        name: "Java / Kotlin",
        lineComment: "//",
        blockComment: ("/*", "*/"),
        multilineStringDelimiters: ["\"\"\""],
        stringDelimiters: ["\"", "'"],
        keywords: [
            "abstract", "as", "assert", "boolean", "break", "byte", "case", "catch", "char",
            "class", "companion", "const", "continue", "data", "default", "do", "double",
            "else", "enum", "extends", "final", "finally", "float", "for", "fun", "if",
            "implements", "import", "in", "instanceof", "int", "interface", "internal", "is",
            "lateinit", "long", "native", "new", "null", "object", "override", "package",
            "private", "protected", "public", "return", "sealed", "short", "static", "super",
            "suspend", "switch", "synchronized", "this", "throw", "throws", "true", "false",
            "try", "val", "var", "void", "volatile", "when", "while",
        ]
    )

    private static let go = LanguageDefinition(
        name: "Go",
        lineComment: "//",
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'", "`"],
        keywords: [
            "break", "case", "chan", "const", "continue", "default", "defer", "else",
            "fallthrough", "false", "for", "func", "go", "goto", "if", "import", "interface",
            "map", "nil", "package", "range", "return", "select", "struct", "switch",
            "true", "type", "var",
        ]
    )

    private static let rust = LanguageDefinition(
        name: "Rust",
        lineComment: "//",
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\""],
        keywords: [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
            "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop",
            "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static",
            "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while",
        ]
    )

    private static let ruby = LanguageDefinition(
        name: "Ruby",
        lineComment: "#",
        stringDelimiters: ["\"", "'"],
        keywords: [
            "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do",
            "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next",
            "nil", "not", "or", "raise", "redo", "rescue", "retry", "return", "self",
            "super", "then", "true", "undef", "unless", "until", "when", "while", "yield",
            "require", "attr_accessor", "attr_reader", "attr_writer",
        ]
    )

    private static let php = LanguageDefinition(
        name: "PHP",
        lineComment: "//",
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'"],
        keywords: [
            "abstract", "array", "as", "break", "case", "catch", "class", "clone", "const",
            "continue", "declare", "default", "do", "echo", "else", "elseif", "extends",
            "final", "finally", "fn", "for", "foreach", "function", "global", "if",
            "implements", "include", "instanceof", "interface", "match", "namespace", "new",
            "null", "print", "private", "protected", "public", "readonly", "require",
            "return", "static", "switch", "throw", "trait", "true", "false", "try", "use",
            "var", "while", "yield",
        ],
        caseInsensitiveKeywords: true
    )

    private static let sql = LanguageDefinition(
        name: "SQL",
        lineComment: "--",
        blockComment: ("/*", "*/"),
        stringDelimiters: ["'"],
        keywords: [
            "select", "from", "where", "insert", "into", "values", "update", "set", "delete",
            "create", "table", "index", "view", "drop", "alter", "add", "column", "primary",
            "key", "foreign", "references", "not", "null", "unique", "default", "and", "or",
            "in", "is", "like", "between", "order", "by", "group", "having", "limit",
            "offset", "join", "inner", "left", "right", "outer", "on", "as", "distinct",
            "count", "sum", "avg", "min", "max", "union", "all", "exists", "case", "when",
            "then", "else", "end", "begin", "commit", "rollback", "transaction",
        ],
        caseInsensitiveKeywords: true
    )

    private static let css = LanguageDefinition(
        name: "CSS",
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'"],
        keywords: ["important", "inherit", "initial", "unset", "auto", "none", "var", "calc"]
    )

    private static let html = LanguageDefinition(
        name: "HTML / XML",
        blockComment: ("<!--", "-->"),
        stringDelimiters: ["\""]
    )

    private static let byExtension: [String: LanguageDefinition] = [
        "swift": swift,
        "py": python,
        "js": javascript, "jsx": javascript, "mjs": javascript,
        "ts": javascript, "tsx": javascript,
        "json": json,
        "yaml": yaml, "yml": yaml,
        "sh": shell, "bash": shell, "zsh": shell,
        "c": c, "h": c, "cpp": c, "cc": c, "hpp": c, "m": c, "mm": c,
        "java": java, "kt": java, "kts": java,
        "go": go,
        "rs": rust,
        "rb": ruby,
        "php": php,
        "sql": sql,
        "css": css,
        "html": html, "htm": html, "xml": html, "svg": html,
    ]
}
