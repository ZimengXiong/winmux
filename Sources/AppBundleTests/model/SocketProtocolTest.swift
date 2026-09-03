@testable import AppBundle
import Common
import Foundation
import Network
import XCTest

final class SocketProtocolTest: XCTestCase {
    func testSocketProtocolVersionStartsAtOne() {
        XCTAssertEqual(SOCKET_PROTOCOL_VERSION, 1)
    }

    func testSocketFrameLimitLeavesHeadroomForWorstCaseCliStdinEncoding() {
        let maxCliStdinBytes = 16 * 1024 * 1024
        let maxEscapedStdinBytes = maxCliStdinBytes * 6

        XCTAssertEqual(MAX_SOCKET_FRAME_BYTES, 128 * 1024 * 1024)
        XCTAssertGreaterThan(Int(MAX_SOCKET_FRAME_BYTES), maxEscapedStdinBytes)
    }

    func testMatchingHandshakeThenFramedRequestRoundTrips() async throws {
        let fixture = try await UnixListenerFixture.make()
        let client = NWConnection(to: .unix(path: fixture.path), using: .tcp)
        let clientHandshake = Task { await client.initConnection(handshakeTimeout: .seconds(1)) }
        let server = try await fixture.acceptConnection()
        defer {
            client.cancel()
            server.cancel()
            fixture.close()
        }

        let serverHandshake = Task { await negotiateSocketProtocolAsServer(server) }
        let serverAccepted = await serverHandshake.value
        let clientResult = await clientHandshake.value
        XCTAssertTrue(serverAccepted)
        XCTAssertNil(clientResult.error)

        let request = ClientRequest(
            args: ["agent", "check", "--stdin"],
            stdin: "{\"schemaVersion\":1,\"edit\":null}\n",
            windowId: nil,
            workspace: nil,
        )
        let requestWriteError = await client.writeAtomic(request).error
        XCTAssertNil(requestWriteError)
        let requestData = try (await server.readNonAtomic()).get()
        let decodedRequest = try JSONDecoder().decode(ClientRequest.self, from: requestData)
        XCTAssertEqual(decodedRequest, request)
        XCTAssertEqual(decodedRequest.stdin, "{\"schemaVersion\":1,\"edit\":null}\n")

        let answer = ServerAnswer(exitCode: 0, stdout: "1", serverVersionAndHash: "test hash")
        let answerWriteError = await server.writeAtomic(answer).error
        XCTAssertNil(answerWriteError)
        let answerData = try (await client.readNonAtomic()).get()
        let decodedAnswer = try JSONDecoder().decode(ServerAnswer.self, from: answerData)
        XCTAssertEqual(decodedAnswer.exitCode, 0)
        XCTAssertEqual(decodedAnswer.stdout, "1")
        XCTAssertEqual(decodedAnswer.serverVersionAndHash, "test hash")
    }

    func testClientRejectsDifferentServerProtocolVersion() async throws {
        let fixture = try await UnixListenerFixture.make()
        let client = NWConnection(to: .unix(path: fixture.path), using: .tcp)
        let clientHandshake = Task { await client.initConnection(handshakeTimeout: .seconds(1)) }
        let server = try await fixture.acceptConnection()
        defer {
            client.cancel()
            server.cancel()
            fixture.close()
        }

        let clientVersion = try (await server.readUInt32()).get()
        XCTAssertEqual(clientVersion, SOCKET_PROTOCOL_VERSION)
        let versionWriteError = await server.writeUInt32(SOCKET_PROTOCOL_VERSION + 1).error
        XCTAssertNil(versionWriteError)

        let result = await clientHandshake.value
        guard case .customError(let message)? = result.error else {
            return XCTFail("Expected a protocol-version error, got \(String(describing: result.error))")
        }
        XCTAssertTrue(message.contains("Client SOCKET_PROTOCOL_VERSION: 1"))
        XCTAssertTrue(message.contains("Server SOCKET_PROTOCOL_VERSION: 2"))
    }

    func testServerReportsItsVersionThenRejectsDifferentClientVersion() async throws {
        let fixture = try await UnixListenerFixture.make()
        let client = NWConnection(to: .unix(path: fixture.path), using: .tcp)
        let clientStart = Task { await client.startBlocking() }
        let server = try await fixture.acceptConnection()
        defer {
            client.cancel()
            server.cancel()
            fixture.close()
        }

        let clientStartResult = await clientStart.value
        XCTAssertNil(clientStartResult.error)
        let serverHandshake = Task { await negotiateSocketProtocolAsServer(server) }
        let versionWriteError = await client.writeUInt32(SOCKET_PROTOCOL_VERSION + 1).error
        XCTAssertNil(versionWriteError)
        let serverVersion = try (await client.readUInt32()).get()
        XCTAssertEqual(serverVersion, SOCKET_PROTOCOL_VERSION)
        let serverAccepted = await serverHandshake.value
        XCTAssertFalse(serverAccepted)
    }

    func testLegacyServerHandshakeTimesOutInsteadOfHanging() async throws {
        let fixture = try await UnixListenerFixture.make()
        let client = NWConnection(to: .unix(path: fixture.path), using: .tcp)
        let clientHandshake = Task { await client.initConnection(handshakeTimeout: .milliseconds(100)) }
        let legacyServer = try await fixture.acceptConnection()
        defer {
            client.cancel()
            legacyServer.cancel()
            fixture.close()
        }

        // A pre-handshake server interprets this value as the length of its
        // first JSON frame and waits for one payload byte forever.
        let firstWord = try (await legacyServer.readUInt32()).get()
        XCTAssertEqual(firstWord, SOCKET_PROTOCOL_VERSION)

        let result = await clientHandshake.value
        guard case .customError(let message)? = result.error else {
            return XCTFail("Expected a bounded legacy-protocol error, got \(String(describing: result.error))")
        }
        XCTAssertTrue(message.contains("Timed out"))
        XCTAssertTrue(message.contains("legacy pre-handshake protocol"))
    }

    func testHandshakeReturnsReadErrorWhenServerClosesWithoutReplying() async throws {
        let fixture = try await UnixListenerFixture.make()
        let client = NWConnection(to: .unix(path: fixture.path), using: .tcp)
        let clientHandshake = Task { await client.initConnection(handshakeTimeout: .seconds(1)) }
        let server = try await fixture.acceptConnection()
        defer {
            client.cancel()
            fixture.close()
        }

        let clientVersion = try (await server.readUInt32()).get()
        XCTAssertEqual(clientVersion, SOCKET_PROTOCOL_VERSION)
        server.cancel()

        let result = await clientHandshake.value
        guard case .nwError? = result.error else {
            return XCTFail("Expected an EOF read error, got \(String(describing: result.error))")
        }
    }

    func testServerRejectsOversizedFrameBeforeWaitingForPayload() async throws {
        let fixture = try await UnixListenerFixture.make()
        let client = NWConnection(to: .unix(path: fixture.path), using: .tcp)
        let clientStart = Task { await client.startBlocking() }
        let server = try await fixture.acceptConnection()
        defer {
            client.cancel()
            server.cancel()
            fixture.close()
        }

        let clientStartResult = await clientStart.value
        XCTAssertNil(clientStartResult.error)

        // Send only an oversized length prefix. A correct implementation must
        // reject it immediately, without allocating or waiting for a payload.
        let prefixWriteError = await client.writeUInt32(MAX_SOCKET_FRAME_BYTES + 1).error
        XCTAssertNil(prefixWriteError)

        switch await server.readNonAtomic() {
            case .failure(.posix(let errorCode)):
                XCTAssertEqual(errorCode, .EMSGSIZE)
            case .failure(let error):
                XCTFail("Expected EMSGSIZE, got \(error)")
            case .success:
                XCTFail("Expected an oversized frame to be rejected")
        }
    }
}

private struct UnixListenerFixture {
    let path: String
    let listener: NWListener
    let connections: AsyncStream<NWConnection>

    static func make() async throws -> UnixListenerFixture {
        let path = "/tmp/winmux-protocol-test-\(UUID().uuidString).sock"
        try? FileManager.default.removeItem(atPath: path)

        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .unix(path: path)
        let listener = try NWListener(using: params)

        let (connections, connectionContinuation) = AsyncStream.makeStream(of: NWConnection.self)
        listener.newConnectionHandler = { connection in
            connectionContinuation.yield(connection)
        }

        let (states, stateContinuation) = AsyncStream.makeStream(of: NWListener.State.self)
        listener.stateUpdateHandler = { state in
            stateContinuation.yield(state)
        }
        listener.start(queue: .global())

        for await state in states {
            switch state {
                case .ready:
                    stateContinuation.finish()
                    return UnixListenerFixture(path: path, listener: listener, connections: connections)
                case .failed(let error):
                    stateContinuation.finish()
                    listener.cancel()
                    throw error
                case .cancelled:
                    stateContinuation.finish()
                    throw NWError.posix(.ECANCELED)
                case .setup, .waiting:
                    continue
                @unknown default:
                    stateContinuation.finish()
                    listener.cancel()
                    throw NWError.posix(.EINVAL)
            }
        }
        throw NWError.posix(.ECANCELED)
    }

    func acceptConnection() async throws -> NWConnection {
        var iterator = connections.makeAsyncIterator()
        guard let connection = await iterator.next() else {
            throw NWError.posix(.ECONNABORTED)
        }
        connection.start(queue: .global())
        return connection
    }

    func close() {
        listener.cancel()
        try? FileManager.default.removeItem(atPath: path)
    }
}
