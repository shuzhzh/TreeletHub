import AppKit
import Darwin
import Foundation

/// Locates and invokes the Codex CLI without Accessibility / key injection.
///
/// The Codex / ChatGPT desktop app ships a full CLI at
/// `…/ChatGPT.app/Contents/Resources/codex`. A separate `npm i -g @openai/codex`
/// install is optional.
///
/// Important: never spawn helper processes (e.g. `/usr/bin/which`) just to probe —
/// App Sandbox aborts the whole app with SIGABRT on disallowed `Process` launches.
enum HubCodexCLI {
    struct ExecResult: Sendable {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    private static let cacheLock = NSLock()
    private static var cachedExecutable: URL??

    /// Real user home (not the App Sandbox container home).
    static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static var codexHomeDirectory: URL {
        realHomeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    static var isCLIAvailable: Bool {
        resolvedExecutableURL() != nil
    }

    /// Only probes known absolute paths via FileManager — no subprocess.
    static func resolvedExecutableURL() -> URL? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cachedExecutable {
            return cached
        }
        let found = probeKnownPaths()
        cachedExecutable = .some(found)
        return found
    }

    /// Clear cache after the user installs / updates Codex mid-session.
    static func invalidateExecutableCache() {
        cacheLock.lock()
        cachedExecutable = nil
        cacheLock.unlock()
    }

    private static func probeKnownPaths() -> URL? {
        var candidates: [String] = []

        // 1) CLI bundled inside the desktop app (ChatGPT / Codex unified app).
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            candidates.append(appURL.appendingPathComponent("Contents/Resources/codex").path)
        }
        candidates.append(contentsOf: [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/OpenAI Codex.app/Contents/Resources/codex"
        ])

        // 2) Standalone CLI installs (Homebrew / npm / local).
        let home = realHomeDirectory.path
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.codex/bin/codex",
            "/usr/bin/codex"
        ])

        let fm = FileManager.default
        for path in candidates {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { continue }
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Run `codex exec` with a prompt.
    static func exec(
        prompt: String,
        sessionId: String? = nil,
        reasoningLevel: String? = nil,
        workingDirectory: URL? = nil
    ) async throws -> ExecResult {
        invalidateExecutableCache()
        guard let exe = resolvedExecutableURL() else {
            throw NSError(
                domain: "TreeletHub",
                code: 3201,
                userInfo: [NSLocalizedDescriptionKey: "未找到 Codex CLI（通常位于 ChatGPT.app 内）。已改为深链接 / 剪贴板方式。"]
            )
        }

        var args: [String] = ["exec"]
        if let sessionId, !sessionId.isEmpty {
            args.append(contentsOf: ["resume", sessionId])
        } else {
            args.append("--skip-git-repo-check")
        }
        if let reasoningLevel, !reasoningLevel.isEmpty {
            args.append(contentsOf: ["-c", "model_reasoning_effort=\(reasoningLevel)"])
        }
        args.append(prompt)

        return try await run(executable: exe, arguments: args, workingDirectory: workingDirectory)
    }

    private static func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL?
    ) async throws -> ExecResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = arguments
                    if let workingDirectory {
                        process.currentDirectoryURL = workingDirectory
                    }
                    // Inherit a minimal environment so bundled CLI can find auth under real home.
                    var env = ProcessInfo.processInfo.environment
                    env["HOME"] = HubCodexCLI.realHomeDirectory.path
                    process.environment = env
                    let out = Pipe()
                    let err = Pipe()
                    process.standardOutput = out
                    process.standardError = err
                    try process.run()
                    process.waitUntilExit()
                    let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(
                        returning: ExecResult(
                            exitCode: process.terminationStatus,
                            stdout: stdout,
                            stderr: stderr
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
