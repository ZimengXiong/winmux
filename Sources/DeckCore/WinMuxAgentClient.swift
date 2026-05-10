import Common
import Foundation
import Network

public struct WinMuxAgentClient: Sendable {
    public init() {}

    public func query() async throws -> DeckAgentSnapshot {
        let answer = try await run(args: ["agent", "query"])
        guard answer.exitCode == 0 else {
            throw DeckError.winMuxUnavailable(answer.stderr.isEmpty ? "WinMux agent query failed." : answer.stderr)
        }
        guard let data = answer.stdout.data(using: .utf8) else {
            throw DeckError.winMuxUnavailable("WinMux agent query returned non-UTF8 output.")
        }
        do {
            return try JSONDecoder().decode(DeckAgentSnapshot.self, from: data)
        } catch {
            throw DeckError.winMuxUnavailable("Failed to decode WinMux agent snapshot: \(error.localizedDescription)")
        }
    }

    func apply(operations: [DeckAgentOperation], worldId: String?) async throws {
        guard !operations.isEmpty else { return }
        let request = DeckAgentApplyRequest(
            schemaVersion: 1,
            worldId: worldId,
            edit: DeckAgentEdit(operations: operations),
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(request)
        let path = FileManager.default.temporaryDirectory
            .appending(path: "deck-agent-\(UUID().uuidString).json")
        try data.write(to: path, options: .atomic)
        defer { try? FileManager.default.removeItem(at: path) }

        let answer = try await run(args: ["agent", "apply", "--path", path.path])
        guard answer.exitCode == 0 else {
            throw DeckError.winMuxUnavailable(answer.stderr.isEmpty ? "WinMux agent apply failed." : answer.stderr)
        }
    }

    public func run(args: [String], stdin: String = "") async throws -> ServerAnswer {
        let connection = NWConnection(to: NWEndpoint.unix(path: socketPath), using: .tcp)
        defer { connection.cancel() }
        if let error = await connection.startBlocking().error {
            throw DeckError.winMuxUnavailable("Can't connect to WinMux server. Is WinMux.app running?\n\(error.localizedDescription)")
        }
        if let error = await connection.writeAtomic(ClientRequest(args: args, stdin: stdin, windowId: nil, workspace: nil)).error {
            throw DeckError.winMuxUnavailable("Failed to write to WinMux server socket: \(error.localizedDescription)")
        }
        switch await connection.readNonAtomic() {
            case .success(let answer):
                return try JSONDecoder().decode(ServerAnswer.self, from: answer)
            case .failure(let error):
                throw DeckError.winMuxUnavailable("Failed to read from WinMux server socket: \(error.localizedDescription)")
        }
    }
}
