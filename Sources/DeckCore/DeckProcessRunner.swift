import Foundation

public struct DeckCommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public protocol DeckProcessRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String?,
        wait: Bool,
    ) async throws -> DeckCommandResult
}

public struct DeckSystemProcessRunner: DeckProcessRunning {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String?,
        wait: Bool,
    ) async throws -> DeckCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            process.environment = environment
            if let currentDirectory {
                process.currentDirectoryURL = URL(filePath: currentDirectory)
            }
            let stdout = Pipe()
            let stderr = Pipe()
            if wait {
                process.standardOutput = stdout
                process.standardError = stderr
            } else {
                process.standardOutput = nil
                process.standardError = nil
            }
            if wait {
                process.terminationHandler = { process in
                    let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(returning: DeckCommandResult(
                        exitCode: process.terminationStatus,
                        stdout: stdoutText,
                        stderr: stderrText,
                    ))
                }
            }
            do {
                try process.run()
                if !wait {
                    continuation.resume(returning: DeckCommandResult(exitCode: 0, stdout: "", stderr: ""))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

public enum DeckShell {
    public static func quote(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
