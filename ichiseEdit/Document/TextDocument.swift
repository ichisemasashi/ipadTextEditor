import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Markdown(Info.plist の UTImportedTypeDeclarations で宣言)
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// プレーンテキスト(UTF-8 のみ)のドキュメント。
/// 改行コードは変換せず、読み込んだ内容をそのまま保持する。
struct TextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .markdownText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // BOM 付き UTF-8 を許容する
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = bytes.dropFirst(3)
        }
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
