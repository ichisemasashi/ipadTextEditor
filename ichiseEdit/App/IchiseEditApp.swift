import SwiftUI

@main
struct IchiseEditApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: TextDocument()) { configuration in
            EditorView(document: configuration.$document)
        }
    }
}
