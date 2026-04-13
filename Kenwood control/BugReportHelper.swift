import Foundation
import AppKit

/// Collects diagnostics and opens a pre-filled GitHub issue for bug reporting.
/// The user clicks "Report a Problem" in the Help menu, a zip is placed on
/// their Desktop with the log + diagnostics, and the browser opens to a
/// pre-filled GitHub issue where they can describe the problem and attach the zip.
enum BugReportHelper {

    private static let repoURL = "https://github.com/w9fyi/ts-890-pro"

    /// Collect diagnostics, zip the log, open a GitHub issue in the browser.
    static func fileReport(radio: RadioState) {
        let diag = collectDiagnostics(radio: radio)
        let zipURL = createDiagnosticZip(diagnostics: diag)
        openGitHubIssue(diagnostics: diag, zipPath: zipURL?.path)

        if let zipURL {
            NSWorkspace.shared.activateFileViewerSelecting([zipURL])
        }
    }

    // MARK: - Diagnostics collection

    private static func collectDiagnostics(radio: RadioState) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let model = radio.radioModel.description
        let status = radio.connectionStatus
        let connType = radio.connectionType.rawValue
        let lastError = DiagnosticsStore.shared.lastError ?? "none"

        let recentErrors = DiagnosticsStore.shared.errorLog.suffix(10)
            .map { "  - \($0)" }
            .joined(separator: "\n")

        let recentLog = radio.connectionLog.suffix(30)
            .map { "  \($0)" }
            .joined(separator: "\n")

        return """
        TS-890 Pro Diagnostic Report
        ============================
        App version: \(version) (\(build))
        macOS: \(os)
        Radio model: \(model)
        Connection type: \(connType)
        Connection status: \(status)
        Last error: \(lastError)

        Recent errors:
        \(recentErrors.isEmpty ? "  (none)" : recentErrors)

        Connection log (last 30 entries):
        \(recentLog.isEmpty ? "  (none)" : recentLog)
        """
    }

    // MARK: - Zip creation

    private static func createDiagnosticZip(diagnostics: String) -> URL? {
        let fm = FileManager.default
        let ts = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("ts890-report-\(ts)")

        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

            // Write diagnostics summary
            let diagFile = tmpDir.appendingPathComponent("diagnostics.txt")
            try diagnostics.write(to: diagFile, atomically: true, encoding: .utf8)

            // Copy the log file if it exists
            let logSource = logFileURL()
            if fm.fileExists(atPath: logSource.path) {
                let logDest = tmpDir.appendingPathComponent("kenwood-control.log")
                try fm.copyItem(at: logSource, to: logDest)
            }

            // Create zip on Desktop
            let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            let zipName = "TS890-Pro-Report-\(ts).zip"
            let zipURL = desktop.appendingPathComponent(zipName)

            // Use ditto for a clean zip
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-c", "-k", "--sequesterRsrc", tmpDir.path, zipURL.path]
            try proc.run()
            proc.waitUntilExit()

            // Clean up temp
            try? fm.removeItem(at: tmpDir)

            if proc.terminationStatus == 0 {
                AppFileLogger.shared.log("Bug report zip created: \(zipURL.path)")
                return zipURL
            }
        } catch {
            AppFileLogger.shared.log("Bug report zip failed: \(error.localizedDescription)")
        }
        return nil
    }

    private static func logFileURL() -> URL {
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return downloads.appendingPathComponent("Kenwood control/kenwood-control.log")
        }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return home.appendingPathComponent("Library/Logs/kenwood-control.log")
    }

    // MARK: - GitHub issue

    private static func openGitHubIssue(diagnostics: String, zipPath: String?) {
        let title = "Bug report"
        let zipNote = zipPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "diagnostic zip"

        let body = """
        ## What happened?

        <!-- Describe what you were doing and what went wrong. -->


        ## Diagnostic zip

        **Please drag `\(zipNote)` from your Desktop into this text area.**
        The zip contains the app log and connection diagnostics.

        ## Environment

        <!-- The diagnostics below were auto-collected by the app. -->

        ```
        \(diagnostics.trimmingCharacters(in: .whitespacesAndNewlines))
        ```
        """

        var components = URLComponents(string: "\(repoURL)/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body)
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }
}
