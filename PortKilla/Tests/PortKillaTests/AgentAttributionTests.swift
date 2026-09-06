import XCTest
@testable import PortKilla

final class AgentAttributionTests: XCTestCase {

    // Build a ProcessTable from (pid, ppid, command) rows.
    private func table(_ rows: [(Int, Int, String)]) -> ProcessTable {
        let lines = rows.map { "\($0.0) \($0.1) 1024 0.0 05:00 \($0.2)" }.joined(separator: "\n")
        return ProcessTable(psOutput: lines)
    }

    private let noEnvironment: AgentAttribution.EnvironmentLookup = { _ in [:] }

    // MARK: - Tree signatures (executable, not args)

    func testMatchesClaudeCodeExecutable() {
        XCTAssertEqual(AgentAttribution.match(command: "claude bg-pty-host --foo"), "Claude Code")
    }

    func testMatchesOtherTerminalAgents() {
        XCTAssertEqual(AgentAttribution.match(command: "/opt/homebrew/bin/codex"), "Codex CLI")
        XCTAssertEqual(AgentAttribution.match(command: "gemini -p hi"), "Gemini CLI")
        XCTAssertEqual(AgentAttribution.match(command: "/usr/local/bin/aider --model x"), "Aider")
    }

    func testMatchesAppBundles() {
        XCTAssertEqual(AgentAttribution.match(command: "/Applications/Cursor.app/Contents/MacOS/Cursor"), "Cursor")
        XCTAssertEqual(AgentAttribution.match(command: "/Applications/Visual Studio Code.app/Contents/MacOS/Code"), "VS Code")
        XCTAssertEqual(AgentAttribution.match(command: "/Applications/Windsurf.app/Contents/MacOS/Windsurf"), "Windsurf")
    }

    func testKernelNameWinsOverSpacedPath() {
        // The CLI bundled inside the desktop app lives under "Application Support";
        // splitting on spaces would yield "Application", so the kernel name decides.
        let path = "/Users/me/Library/Application Support/Claude/claude-code/2.1.0/claude.app/Contents/MacOS/claude --flag"
        XCTAssertEqual(AgentAttribution.match(command: path, executableName: "claude"), "Claude Code")
        XCTAssertNil(AgentAttribution.match(command: path))
    }

    func testDesktopAppIsNotTheCli() {
        XCTAssertNil(AgentAttribution.match(command: "/Applications/Claude.app/Contents/MacOS/Claude", executableName: "Claude"))
    }

    func testDoesNotMatchProjectFolderNamedClaude() {
        // Regression: a project path containing "claude-code" must NOT be
        // attributed to Claude Code; only the executable counts.
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
        let owner = AgentAttribution.owner(ofPid: 300, in: t, environmentOf: noEnvironment)
        XCTAssertEqual(owner?.name, "Claude Code")
        XCTAssertEqual(owner?.sessionPid, 100)
        XCTAssertEqual(owner?.source, .processTree)
    }

    func testSessionIsTheCliNotTheDesktopAppAboveIt() {
        // desktop Claude(50) -> claude CLI(100) -> zsh(200) -> server(300)
        let t = table([
            (50, 1, "/Applications/Claude.app/Contents/MacOS/Claude"),
            (100, 50, "claude"),
            (200, 100, "/bin/zsh"),
            (300, 200, "node server.js"),
        ])
        XCTAssertEqual(AgentAttribution.owner(ofPid: 300, in: t, environmentOf: noEnvironment)?.sessionPid, 100)
    }

    func testUnattributedWhenNoAgentAncestorAndNoMarkers() {
        let t = table([
            (200, 1, "/sbin/launchd"),
            (300, 200, "node server.js"),
        ])
        XCTAssertNil(AgentAttribution.owner(ofPid: 300, in: t, environmentOf: noEnvironment))
    }

    func testStopsAtRootWithoutInfiniteLoop() {
        // A cycle must not hang the walk.
        let t = table([(300, 300, "node server.js")])
        XCTAssertNil(AgentAttribution.owner(ofPid: 300, in: t, environmentOf: noEnvironment))
    }

    // MARK: - Environment markers (survive reparenting)

    func testDetachedServerAttributedByEnvironment() {
        // The shell that started the server is gone: server(300) -> launchd.
        // The CLAUDECODE marker it inherited still names the owner.
        let t = table([(300, 1, "node server.js")])
        let owner = AgentAttribution.owner(ofPid: 300, in: t) { pid in
            pid == 300 ? ["CLAUDECODE": "1", "CLAUDE_PID": "4242"] : [:]
        }
        XCTAssertEqual(owner?.name, "Claude Code")
        XCTAssertEqual(owner?.sessionPid, 4242)
        XCTAssertEqual(owner?.source, .environment)
    }

    func testAncestryWinsOverEnvironment() {
        // Both signals present: the tree is session-precise, so it wins.
        let t = table([
            (100, 1, "claude"),
            (300, 100, "node server.js"),
        ])
        let owner = AgentAttribution.owner(ofPid: 300, in: t) { _ in ["CLAUDECODE": "1", "CLAUDE_PID": "999"] }
        XCTAssertEqual(owner?.sessionPid, 100)
        XCTAssertEqual(owner?.source, .processTree)
    }

    func testTerminalAgentOutranksEditorMarker() {
        // Claude Code running inside a Cursor terminal stamps both markers.
        let env = ["CLAUDECODE": "1", "CURSOR_TRACE_ID": "abc", "TERM_PROGRAM": "vscode"]
        XCTAssertEqual(AgentAttribution.ownerFromEnvironment(env)?.name, "Claude Code")
    }

    func testEditorMarkers() {
        XCTAssertEqual(AgentAttribution.ownerFromEnvironment(["CURSOR_TRACE_ID": "x", "TERM_PROGRAM": "vscode"])?.name, "Cursor")
        XCTAssertEqual(AgentAttribution.ownerFromEnvironment(["TERM_PROGRAM": "vscode"])?.name, "VS Code")
        XCTAssertNil(AgentAttribution.ownerFromEnvironment(["TERM_PROGRAM": "iTerm.app"]))
    }

    func testSessionPidIgnoredWhenNotNumeric() {
        let owner = AgentAttribution.ownerFromEnvironment(["CLAUDECODE": "1", "CLAUDE_PID": "nope"])
        XCTAssertEqual(owner?.name, "Claude Code")
        XCTAssertNil(owner?.sessionPid)
    }

    func testOnlyAllowlistedKeysAreRequested() {
        // The scanner must never be asked for anything beyond the markers.
        XCTAssertEqual(AgentAttribution.markerKeys,
                       ["CLAUDECODE", "GEMINI_CLI", "CURSOR_TRACE_ID", "TERM_PROGRAM", "CLAUDE_PID"])
    }

    // MARK: - Caller identity

    func testDeclaredOwnerWins() {
        let t = table([(300, 1, "/sbin/launchd")])
        let owner = AgentAttribution.callerOwner(callerPid: 300, in: t,
                                                 environment: ["PORTKILLA_OWNER": "my-bot", "CLAUDECODE": "1"])
        XCTAssertEqual(owner?.name, "my-bot")
        XCTAssertNil(owner?.sessionPid)
        XCTAssertEqual(owner?.source, .declared)
    }

    func testCallerFallsBackToOwnEnvironment() {
        // A CLI invoked by an agent through a shell that already exited.
        let t = table([(300, 1, "portkilla kill 3000")])
        let owner = AgentAttribution.callerOwner(callerPid: 300, in: t,
                                                 environment: ["CLAUDECODE": "1", "CLAUDE_PID": "77"])
        XCTAssertEqual(owner?.name, "Claude Code")
        XCTAssertEqual(owner?.sessionPid, 77)
    }

    // MARK: - Friendly-fire decision

    func testDifferentAgentsIsFriendlyFire() {
        let cursor = AgentOwner(name: "Cursor", sessionPid: 10, source: .processTree)
        let claude = AgentOwner(name: "Claude Code", sessionPid: 20, source: .processTree)
        XCTAssertTrue(AgentAttribution.isFriendlyFire(caller: cursor, target: claude))
    }

    func testSameAgentDifferentSessionIsFriendlyFire() {
        let a = AgentOwner(name: "Claude Code", sessionPid: 10, source: .processTree)
        let b = AgentOwner(name: "Claude Code", sessionPid: 99, source: .environment)
        XCTAssertTrue(AgentAttribution.isFriendlyFire(caller: a, target: b))
    }

    func testSameSessionAcrossSourcesIsAllowed() {
        // Tree finds the claude pid; env carries CLAUDE_PID with the same value.
        let fromTree = AgentOwner(name: "Claude Code", sessionPid: 10, source: .processTree)
        let fromEnv = AgentOwner(name: "Claude Code", sessionPid: 10, source: .environment)
        XCTAssertFalse(AgentAttribution.isFriendlyFire(caller: fromTree, target: fromEnv))
    }

    func testUnknownOwnerNeverBlocks() {
        let claude = AgentOwner(name: "Claude Code", sessionPid: 10, source: .processTree)
        XCTAssertFalse(AgentAttribution.isFriendlyFire(caller: nil, target: claude))
        XCTAssertFalse(AgentAttribution.isFriendlyFire(caller: claude, target: nil))
    }

    func testSameNameUnknownSessionAllowed() {
        // Same tool, session unknown on one side: allow (never block on a guess).
        let declared = AgentOwner(name: "Claude Code", sessionPid: nil, source: .declared)
        let target = AgentOwner(name: "Claude Code", sessionPid: 55, source: .processTree)
        XCTAssertFalse(AgentAttribution.isFriendlyFire(caller: declared, target: target))
    }
}
