import XCTest
@testable import PortNannyCore
@testable import PortNanny

final class MCPServerTests: XCTestCase {
    private let server = MCPServer()

    private func json(_ line: String?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(line).utf8)) as? [String: Any])
    }

    func testInitializeHandshake() throws {
        let reply = try json(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}"#))
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, MCPServer.protocolVersion)
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "portnanny")
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#), "notifications get no reply")
    }

    func testToolsListNamesEveryTool() throws {
        let reply = try json(server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let tools = try XCTUnwrap((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }),
                       ["list_ports", "kill_port", "whois_port", "whoami", "wait_for_port_free", "free_port", "reserve_port", "release_port"])
        for tool in tools {
            XCTAssertNotNil(tool["inputSchema"], "\(tool["name"] ?? "") needs a schema")
        }
    }

    func testWhoamiToolReturnsStructuredContent() throws {
        let reply = try json(server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"whoami","arguments":{}}}"#))
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let structured = try XCTUnwrap(result["structuredContent"] as? [String: Any])
        XCTAssertNotNil(structured["detected"])
    }

    func testWhoisPortOnAFreePortIsEmptyNotAnError() throws {
        let reply = try json(server.handle(line: #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"whois_port","arguments":{"port":65001}}}"#))
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let structured = try XCTUnwrap(result["structuredContent"] as? [String: Any])
        XCTAssertEqual(structured["exitCode"] as? Int, 1)
        XCTAssertEqual((structured["targets"] as? [Any])?.count, 0)

        let missing = try json(server.handle(line: #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"whois_port","arguments":{}}}"#))
        XCTAssertEqual((missing["result"] as? [String: Any])?["isError"] as? Bool, true)
    }

    func testKillPortDryRunOnAFreePortIsNotFoundNotAnError() throws {
        let reply = try json(server.handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"kill_port","arguments":{"port":65001}}}"#))
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        let structured = try XCTUnwrap(result["structuredContent"] as? [String: Any])
        XCTAssertEqual(structured["action"] as? String, "not-found")
        XCTAssertEqual(result["isError"] as? Bool, false)
    }

    func testErrorsFollowJSONRPC() throws {
        let unknown = try json(server.handle(line: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"nope"}}"#))
        XCTAssertEqual(((unknown["error"] as? [String: Any])?["code"] as? Int), -32602)
        let missing = try json(server.handle(line: #"{"jsonrpc":"2.0","id":6,"method":"resources/list"}"#))
        XCTAssertEqual(((missing["error"] as? [String: Any])?["code"] as? Int), -32601)
        let garbage = try json(server.handle(line: "this is not json"))
        XCTAssertEqual(((garbage["error"] as? [String: Any])?["code"] as? Int), -32700)
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"ping"}"#), "a request without an id is a notification")
    }

    func testReplyIsOneLineOfJSON() throws {
        let reply = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#))
        XCTAssertFalse(reply.contains("\n"), "newline-delimited framing")
    }
}
