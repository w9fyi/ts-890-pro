import Foundation

/// Minimal always-on file logger for VoiceOver-friendly debugging.
final class AppFileLogger {

    nonisolated deinit {}
    static let shared = AppFileLogger()

    private let queue = DispatchQueue(label: "AppFileLogger.queue")
    private let url: URL = {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport.appendingPathComponent("TS-890 Pro/kenwood-control.log")
        }

        let home = URL(fileURLWithPath: NSHomeDirectory())
        return home.appendingPathComponent("Library/Application Support/TS-890 Pro/kenwood-control.log")
    }()
    private let maxBytes: Int = 5 * 1024 * 1024
    private let keepTailBytes: Int = 1 * 1024 * 1024

    private init() {}

    func log(_ message: String) {
        queue.async {
            self.rotateIfNeeded()
            self.appendLine(message)
        }
    }

    func logSync(_ message: String) {
        queue.sync {
            self.rotateIfNeeded()
            self.appendLine(message)
        }
    }

    func logLaunchHeader() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        logSync("=== Launch \(Self.timestamp()) v\(version) (\(build)) pid=\(ProcessInfo.processInfo.processIdentifier) ===")
        logSync("Log path: \(url.path)")
    }

    private func appendLine(_ message: String) {
        let line = "[\(Self.timestamp())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            // Ensure directory exists.
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Logging must never break app behavior, but we still want a breadcrumb in unified logs.
            AppLogger.error("File log write failed: \(error.localizedDescription) path=\(url.path)")
        }
    }

    private func rotateIfNeeded() {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            guard size > maxBytes else { return }

            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            let tail = try handle.readToEnd() ?? Data()
            let trimmed = tail.suffix(keepTailBytes)
            try trimmed.write(to: url, options: .atomic)
            appendLine("=== log rotated (kept last \(keepTailBytes) bytes) ===")
        } catch {
            // Ignore.
        }
    }

    private static func timestamp() -> String {
        // ISO-like but without timezone noise; local time is fine for single-machine debugging.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
