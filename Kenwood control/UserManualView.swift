import SwiftUI

/// Displays the bundled UserManual.md in a scrollable, VoiceOver-friendly window.
struct UserManualView: View {
    @State private var content: AttributedString = AttributedString("Loading…")

    var body: some View {
        ScrollView {
            Text(content)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear { loadManual() }
    }

    private func loadManual() {
        guard let url = Bundle.main.url(forResource: "UserManual", withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8),
              let attributed = try? AttributedString(
                  markdown: raw,
                  options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
              )
        else {
            content = AttributedString("User manual not found.")
            return
        }
        content = attributed
    }
}
