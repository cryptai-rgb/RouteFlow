import Foundation

actor PrivilegedExecutor {

    /// Execute a command with administrator privileges via AppleScript.
    /// macOS will show a system authentication dialog for the user to enter their admin password.
    func executePrivilegedCommand(_ command: String, arguments: [String]) async throws -> String {
        try await executePrivilegedScript(Self.buildShellCommand(command, arguments: arguments))
    }

    /// Execute a full shell script with administrator privileges.
    func executePrivilegedScript(_ script: String) async throws -> String {
        try await runAppleScriptAdmin(script)
    }

    /// Execute a command without privileges (e.g. `route get`).
    func executeCommand(_ command: String, arguments: [String]) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let errorMsg = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw PrivilegedError.commandFailed(exitCode: Int(process.terminationStatus), message: errorMsg)
        }

        return String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Private

    private func runAppleScriptAdmin(_ command: String) async throws -> String {
        // Escape double quotes and backslashes for AppleScript string
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = "do shell script \"\(escaped)\" with administrator privileges"

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                let errPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                process.standardOutput = pipe
                process.standardError = errPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errPipe.fileHandleForReading.readDataToEndOfFile()

                    if process.terminationStatus != 0 {
                        let errorMsg = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                        // User cancelled the authentication dialog (exit code -128 or 1)
                        if errorMsg.contains("-128") || errorMsg.contains("User canceled") {
                            continuation.resume(throwing: PrivilegedError.userCancelled)
                        } else {
                            continuation.resume(throwing: PrivilegedError.commandFailed(exitCode: Int(process.terminationStatus), message: errorMsg))
                        }
                    } else {
                        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func buildShellCommand(_ command: String, arguments: [String]) -> String {
        let renderedArguments = arguments.map(Self.shellEscape).joined(separator: " ")
        guard !renderedArguments.isEmpty else { return command }
        return "\(command) \(renderedArguments)"
    }

    static func shellEscape(_ arg: String) -> String {
        // Simple shell escaping: wrap in single quotes, escape internal single quotes
        let escaped = arg.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    enum PrivilegedError: LocalizedError {
        case userCancelled
        case commandFailed(exitCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .userCancelled:
                return L10n.tr("common.authentication_cancelled")
            case .commandFailed(let code, let msg):
                return L10n.fmt("common.command_failed", code, msg)
            }
        }
    }
}
