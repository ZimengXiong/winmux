@testable import Cli
import Common
import Foundation
import XCTest

final class AgentCliStdinTest: XCTestCase {
    func testAgentStdinIsReadOnlyWhenExplicitlyRequested() throws {
        let stdinArgs = try XCTUnwrap(parseCmdArgs(["agent", "apply", "--stdin"]).cmdOrNil)
        let pathArgs = try XCTUnwrap(parseCmdArgs(["agent", "apply", "--path", "/tmp/request.json"]).cmdOrNil)
        let queryArgs = try XCTUnwrap(parseCmdArgs(["agent", "query"]).cmdOrNil)

        XCTAssertTrue(shouldReadAgentStdin(stdinArgs))
        XCTAssertFalse(shouldReadAgentStdin(pathArgs))
        XCTAssertFalse(shouldReadAgentStdin(queryArgs))
    }

    func testBoundedUtf8StdinReaderAcceptsChunkedUtf8AtLimit() {
        var chunks = [Data("hello ".utf8), Data("world".utf8)]

        let result = readBoundedUtf8Stdin(maxBytes: 11) { _ in
            chunks.isEmpty ? nil : chunks.removeFirst()
        }

        XCTAssertEqual(result.getOrNil(), "hello world")
    }

    func testBoundedUtf8StdinReaderRejectsInputOverLimit() {
        var chunks = [Data("123456".utf8)]

        let result = readBoundedUtf8Stdin(maxBytes: 5) { _ in
            chunks.isEmpty ? nil : chunks.removeFirst()
        }

        XCTAssertEqual(result.failureOrNil, "stdin size limit of 5 bytes is exceeded")
    }

    func testBoundedUtf8StdinReaderRejectsInvalidUtf8() {
        var chunks = [Data([0xC3, 0x28])]

        let result = readBoundedUtf8Stdin(maxBytes: 10) { _ in
            chunks.isEmpty ? nil : chunks.removeFirst()
        }

        XCTAssertEqual(result.failureOrNil, "stdin is not valid UTF-8")
    }
}
