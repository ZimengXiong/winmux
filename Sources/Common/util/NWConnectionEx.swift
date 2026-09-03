import Foundation
import Network

extension NWConnection {
    public func writeAtomic(_ msg: Codable, _ encoder: JSONEncoder = JSONEncoder()) async -> ((), error: NWError?) {
        let payload = Result { try encoder.encode(msg) }.getOrDie()
        var data = withUnsafeBytes(of: UInt32(payload.count)) { Data($0) }
        check(data.count == 4)
        data.append(payload)
        return await withCheckedContinuation { cont in
            send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(returning: ((), error))
                } else {
                    cont.resume(returning: ((), nil))
                }
            })
        }
    }

    public func startBlocking() async -> ((), error: NWError?) {
        await withCheckedContinuation { cont in
            let isDone = IsDone()
            stateUpdateHandler = { state in
                Task {
                    let error: NWError?
                    switch state {
                        case .cancelled, .preparing, .setup: return
                        case .ready: error = nil
                        case .failed(let e), .waiting(let e): error = e
                        @unknown default: die("Unknown NWConnection.State: \(state)")
                    }
                    // Make sure to resume continuation only once
                    if await isDone.markAsDone().wasAlreadyDone {
                        return
                    }
                    self.stateUpdateHandler = nil
                    cont.resume(returning: ((), error))
                }
            }
            start(queue: .global())
        }
    }

    /// Starts a client connection and performs the one-shot socket protocol
    /// handshake before any framed JSON is exchanged.
    public func initConnection(handshakeTimeout: Duration = .seconds(2)) async -> ((), error: InitConnectionError?) {
        if let error = await startBlocking().error {
            return ((), .nwError(error))
        }

        if let error = await writeUInt32(SOCKET_PROTOCOL_VERSION).error {
            return ((), .nwError(error))
        }

        let deadline = HandshakeDeadline()
        let timeoutTask = Task<Void, Never> {
            do {
                try await Task.sleep(for: handshakeTimeout)
            } catch {
                return
            }
            if await deadline.timeOutIfPending() {
                self.cancel()
            }
        }

        let serverVersionResult = await readUInt32()
        let didTimeOut = await deadline.finish()
        timeoutTask.cancel()

        if didTimeOut {
            return (
                (),
                .customError(
                    """
                    Timed out while negotiating the WinMux socket protocol.
                    The running WinMux.app may use the legacy pre-handshake protocol. Update and restart WinMux.app and the winmux CLI together.
                    """,
                ),
            )
        }

        switch serverVersionResult {
            case .success(let serverVersion) where serverVersion != SOCKET_PROTOCOL_VERSION:
                return (
                    (),
                    .customError(
                        """
                        Client SOCKET_PROTOCOL_VERSION: \(SOCKET_PROTOCOL_VERSION)
                        Server SOCKET_PROTOCOL_VERSION: \(serverVersion)

                        The client and server protocols are incompatible. Install WinMux.app and the winmux CLI as a matched pair, then restart WinMux.
                        """,
                    ),
                )
            case .success:
                return ((), nil)
            case .failure(let error):
                return ((), .nwError(error))
        }
    }

    public enum InitConnectionError: Sendable {
        case nwError(NWError)
        case customError(String)
    }

    private func read(bytes size: Int) async -> Result<Data, NWError> {
        var data = Data(capacity: size)
        while data.count < size {
            let remaining = size - data.count
            let chunk: Result<Data, NWError> = await withCheckedContinuation { cont in
                receive(minimumIncompleteLength: remaining, maximumLength: remaining) { data, context, isComplete, error in
                    if let error {
                        cont.resume(returning: .failure(error))
                    } else if let data, !data.isEmpty {
                        cont.resume(returning: .success(data))
                    } else {
                        // Network.framework represents an orderly peer close as
                        // an empty successful read. Treat it as EOF instead of
                        // spinning forever without making progress.
                        cont.resume(returning: .failure(.posix(.ECONNRESET)))
                    }
                }
            }
            switch chunk {
                case .success(let chunk): data.append(chunk)
                case .failure: return chunk
            }
        }
        return .success(data)
    }

    public func readTillError() async {
        while true {
            let isError = await withCheckedContinuation { cont in
                receive(minimumIncompleteLength: 1, maximumLength: Int.max) { data, context, isComplete, error in
                    cont.resume(returning: error != nil || data == nil || data?.count == 0)
                }
            }
            if isError { return }
        }
    }

    public func readUInt32() async -> Result<UInt32, NWError> {
        await read(bytes: 4).map { data in
            data.withUnsafeBytes { $0.load(as: UInt32.self) }
        }
    }

    public func writeUInt32(_ int: UInt32) async -> ((), error: NWError?) {
        let data = withUnsafeBytes(of: int) { Data($0) }
        check(data.count == 4)
        return await withCheckedContinuation { cont in
            send(content: data, completion: .contentProcessed { error in
                cont.resume(returning: ((), error))
            })
        }
    }

    public func readNonAtomic() async -> Result<Data, NWError> {
        switch await readUInt32() {
            case .success(let count):
                // Validate the peer-controlled length before read(bytes:)
                // reserves storage for the payload.
                guard count <= MAX_SOCKET_FRAME_BYTES else {
                    return .failure(.posix(.EMSGSIZE))
                }
                return await read(bytes: Int(count))
            case .failure(let e):
                return .failure(e)
        }
    }
}

private actor IsDone {
    private var isDone: Bool = false

    func markAsDone() -> (wasAlreadyDone: Bool, ()) {
        let old = isDone
        isDone = true
        return (old, ())
    }
}

private actor HandshakeDeadline {
    private enum State {
        case pending
        case finished
        case timedOut
    }

    private var state: State = .pending

    func timeOutIfPending() -> Bool {
        guard state == .pending else { return false }
        state = .timedOut
        return true
    }

    func finish() -> Bool {
        switch state {
            case .pending:
                state = .finished
                return false
            case .finished:
                return false
            case .timedOut:
                return true
        }
    }
}
