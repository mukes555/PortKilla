import XCTest
@testable import PortKilla

final class AgentAttributionTests: XCTestCase {

    // Build a ProcessTable from (pid, ppid, command) rows.
    private func table(_ rows: [(Int, Int, String)]) -> ProcessTable {
        let lines = rows.map { "\($0.0) \($0.1) 1024 0.0 05:00 \($0.2)" }.joined(separator: "\n")
        return ProcessTable(psOutput: lines)
    }

    // MARK: - Signature matching (executable, not args)

    func testMatchesClaudeCodeExecutable() {
        XCTAssertEqual(AgentAttribution.match(command: "claude bg-pty-host --foo"), "Claude Code")
    }

    func testMatchesAppBundles() {
        XCTAssertEqual(AgentAttribution.match(command: "/Applications/Cursor.app/Contents/MacOS/Cursor"), "Cursor")
        XCTAssertEqual(AgentAttribution.match(command: "/Applications/Visual Studio Code.app/Contents/MacOS/Code"), "VS Code")
        XCTAssertEqual(AgentAttribution.match(command: "/Applications/Windsurf.app/Contents/MacOS/Windsurf"), "Windsurf")
    }

    func testDoesNotMatchProjectFolderNamedClaude() {
        // Regression: a project path containing "claude-code" must NOT be
        // attributed to Claude Code — only the executable counts.
        XCTAssertNil(AgentAttribution.match(command: "node /Users/me/Documents/claude-code/app/server.js"))
    }

    // MARK: - Ancestry walk

    func testWalksAncestryToAgent() {
        // server(300) -> shell(200) -> claude(100)
        let t = table([
            (100, 1, "claude bg-pty-host"),
            (200, 100, "/bin/zsh"),
            (300, 200, "node /Users/me/projects/app/server.js"),
        ])
        let owner = AgentAttribution.owner(ofPid: 300, in: t)
        XCTAssertEqual(owner?.name, "Claude Code")
        XCTAssertEqual(owner?.sessionPid, 100)
    }

    func testUnattributedWhenNoAgentAncestor() {
        let t = table([
            (200, 1, "/sbin/launchd"),
            (300, 200, "node server.js"),
        ])
        XCTAssertNil(AgentAttribution.owner(ofPid: 300, in: t))
    }

    func testStopsAtRootWithoutInfiniteLoop() {
        // A cycle must not hang the walk.
        let t = table([(300, 300, "node server.js")])
        XCTAssertNil(AgentAttribution.owner(ofPid: 300, in: t))
    }

    // MARK: - Caller owner + env override

    func testEnvOverrideWins() {
        let t = table([(300, 1, "/sbin/launchd")])
        let owner = AgentAttribution.callerOwner(callerPid: 300, in: t, environment: ["PORTKILLA_OWNER": "my-bot"])
        XCTAssertEqual(owner?.name, "my-bot")
        XCTAssertNil(owner?.sessionPid) // declared, not detected
    }

    // MARK: - Friendly-fire decision

    func testDifferentAgentsIsFriendlyFire() {
        let cursor = AgentOwner(name: "Cursor", sessionPid: 10)
        let claude = AgentOwner(name: "Claude Code", sessionPid: 20)
        XCTAssertTrue(AgentAttribution.isFriendlyFire(caller: cursor, target: claude))
    }

    func testSameAgentDifferentSessionIsFriendlyFire() {
        let a = AgentOwner(name: "Claude Code", sessionPid: 10)
        let b = AgentOwner(name: "Claude Code", sessionPid: 99)
        XCTAssertTrue(AgentAttribution.isFriendlyFire(caller: a, target: b))
    }

    func testSameSessionIsAllowed() {
        let a = AgentOwner(name: "Claude Code", sessionPid: 10)
        XCTAssertFalse(AgentAttribution.isFriendlyFire(caller: a, target: a))
    }

    func testUnknownOwnerNeverBlocks() {
        let claude = AgentOwner(name: "Claude Code", sessionPid: 10)
        XCTAssertFalse(AgentAttribution.isFriendlyFire(caller: nil, target: claude))
        XCTAssertFalse(AgentAttribution.isFriendlyFire(caller: claude, target: nil))
    }

    func testEnvOwnerSameNameUnknownSessionAllowed() {
        // PORTKILLA_OWNER=Claude Code killing a Claude Code port: same tool,
        // session unknown -> allow (don't block your own kind on a guess).
        let declared = AgentOwner(name: "Claude Code", sessionPid: nil)
        let target = AgentOwner(name: "Claude Code", sessionPid: 55)
        XCTAssertFalse(AgentAttribution.isFriendlyFire(caller: declared, target: target))
    }
}
