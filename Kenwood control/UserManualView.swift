import SwiftUI

/// Displays the bundled UserManual.md in a scrollable, VoiceOver-friendly window.
/// Splits the markdown by section headings for lazy rendering and heading navigation.
struct UserManualView: View {
    @State private var sections: [ManualSection] = []
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                TextField("Search manual…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search manual")
                if !searchText.isEmpty {
                    Button("Clear") { searchText = "" }
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(filteredSections) { section in
                        ManualSectionView(section: section)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear { loadManual() }
    }

    private var filteredSections: [ManualSection] {
        guard !searchText.isEmpty else { return sections }
        let query = searchText.lowercased()
        return sections.filter { $0.rawText.lowercased().contains(query) }
    }

    private func loadManual() {
        guard let url = Bundle.main.url(forResource: "UserManual", withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8)
        else {
            sections = [ManualSection(id: 0, heading: "Error", headingLevel: 1,
                                      body: AttributedString("User manual not found."),
                                      rawText: "User manual not found.")]
            return
        }
        sections = parseMarkdownSections(raw)
    }
}

// MARK: - Model

struct ManualSection: Identifiable {
    let id: Int
    let heading: String
    let headingLevel: Int   // 1 = #, 2 = ##, 3 = ###
    let body: AttributedString
    let rawText: String
}

// MARK: - Section View

private struct ManualSectionView: View {
    let section: ManualSection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Heading
            Text(section.heading)
                .font(headingFont)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(accessibilityLevel)

            // Body content
            if !section.body.characters.isEmpty {
                Text(section.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var headingFont: Font {
        switch section.headingLevel {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }

    private var accessibilityLevel: AccessibilityHeadingLevel {
        switch section.headingLevel {
        case 1: return .h1
        case 2: return .h2
        case 3: return .h3
        case 4: return .h4
        default: return .unspecified
        }
    }
}

// MARK: - Markdown Parser

/// Split markdown text into sections at heading boundaries.
/// Each section contains the heading and all content until the next heading.
private func parseMarkdownSections(_ markdown: String) -> [ManualSection] {
    let lines = markdown.components(separatedBy: "\n")
    var sections: [ManualSection] = []
    var currentHeading = ""
    var currentLevel = 1
    var currentLines: [String] = []
    var sectionIndex = 0

    func flushSection() {
        let bodyText = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let attributed: AttributedString
        if bodyText.isEmpty {
            attributed = AttributedString()
        } else if let parsed = try? AttributedString(
            markdown: bodyText,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            attributed = parsed
        } else {
            attributed = AttributedString(bodyText)
        }

        if !currentHeading.isEmpty || !bodyText.isEmpty {
            sections.append(ManualSection(
                id: sectionIndex,
                heading: currentHeading,
                headingLevel: currentLevel,
                body: attributed,
                rawText: currentHeading + " " + bodyText
            ))
            sectionIndex += 1
        }
    }

    for line in lines {
        if line.hasPrefix("#") {
            // Flush previous section
            flushSection()
            currentLines = []

            // Parse heading level
            var level = 0
            for ch in line {
                if ch == "#" { level += 1 } else { break }
            }
            currentLevel = level
            currentHeading = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        } else {
            currentLines.append(line)
        }
    }

    // Flush last section
    flushSection()

    return sections
}
