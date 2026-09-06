import XCTest
@testable import PortKilla

final class AgentDocsInstallerTests: XCTestCase {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("portkilla-docs-\(UUID().uuidString).md")
    }

    func testInstallIsIdempotentAndUpdatesInPlace() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try "# My project\n\nSome rules.\n".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(try AgentDocsInstaller.install(into: file), .added)
        let once = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(once.hasPrefix("# My project"))
        XCTAssertEqual(once.components(separatedBy: AgentDocsInstaller.beginMarker).count, 2)

        XCTAssertEqual(try AgentDocsInstaller.install(into: file), .unchanged)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), once)

        // A stale block is replaced, not duplicated.
        let stale = once.replacingOccurrences(of: "portkilla free", with: "portkilla kill")
        try stale.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(try AgentDocsInstaller.install(into: file), .updated)
        let updated = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(updated.components(separatedBy: AgentDocsInstaller.beginMarker).count, 2)
        XCTAssertTrue(updated.contains("portkilla free"))
    }

    func testInstallCreatesTheFileWhenMissing() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try AgentDocsInstaller.install(into: file), .added)
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).hasPrefix(AgentDocsInstaller.beginMarker))
    }

    func testArgumentsParse() {
        var options = CLICommand.AgentDocsOptions()
        XCTAssertEqual(CLIArguments.parse(["agent-docs"]), .success(.agentDocs(options)))
        options.write = true
        options.file = "AGENTS.md"
        XCTAssertEqual(CLIArguments.parse(["agent-docs", "--write", "--file", "AGENTS.md"]), .success(.agentDocs(options)))
        XCTAssertEqual(CLIArguments.parse(["agent-docs", "--install"]), .failure(.unknownOption("--install", command: "agent-docs")))
        XCTAssertEqual(CLIArguments.parse(["mcp"]), .success(.mcp))
        XCTAssertEqual(CLIArguments.parse(["mcp", "--setup"]), .success(.mcpSetup(agent: nil)))
        XCTAssertEqual(CLIArguments.parse(["mcp", "--setup", "cursor"]), .success(.mcpSetup(agent: "cursor")))
        XCTAssertEqual(CLIArguments.parse(["mcp", "--setup", "emacs"]), .failure(.unknownOption("emacs", command: "mcp --setup")))
        XCTAssertTrue(MCPSetup.instructions(for: "claude").contains("claude mcp add portkilla"))
        for agent in ["claude", "cursor", "codex"] {
            XCTAssertTrue(MCPSetup.instructions(for: nil).contains(MCPSetup.agents[agent]!.split(separator: "\n").first!))
        }
        XCTAssertTrue(AgentDocsInstaller.claudeHook.contains("PreToolUse"))
    }
}
