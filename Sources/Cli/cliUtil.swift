import Common
import Darwin
import Foundation

let cliClientVersionAndHash: String = "\(winMuxAppVersion) \(gitHash)"
let maxAgentStdinBytes = 16 * 1024 * 1024
private let stdinReadChunkBytes = 64 * 1024

func hasStdin() -> Bool {
    isatty(STDIN_FILENO) != 1
}

func readBoundedUtf8Stdin(
    maxBytes: Int = maxAgentStdinBytes,
    readChunk: (Int) throws -> Data? = { try FileHandle.standardInput.read(upToCount: $0) },
) -> Result<String, String> {
    guard maxBytes >= 0 else {
        return .failure("stdin byte limit must not be negative")
    }

    var data = Data()
    do {
        while true {
            let remainingBytes = maxBytes - data.count
            let bytesToRead = remainingBytes >= stdinReadChunkBytes ? stdinReadChunkBytes : remainingBytes + 1
            guard let chunk = try readChunk(bytesToRead), !chunk.isEmpty else { break }
            data.append(chunk)
            if data.count > maxBytes {
                return .failure("stdin size limit of \(maxBytes) bytes is exceeded")
            }
        }
    } catch {
        return .failure("Failed to read stdin: \(error.localizedDescription)")
    }

    guard let input = String(data: data, encoding: .utf8) else {
        return .failure("stdin is not valid UTF-8")
    }
    return .success(input)
}
