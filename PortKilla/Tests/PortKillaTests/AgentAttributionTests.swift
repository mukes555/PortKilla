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
        XCTAssertEqual(AgentAttribution.match(command: "claude bg-pty-host --foo")?.name, "Claude Code")
        XCTAssertEqual(AgentAttribution.match(command: "claude")?.confidence, .agent)
    }

    func testMatchesOtherTerminalAgents() {
        XCTAssertEqual(AgentAttribution.match(command: "/opt/homebrew/bin/codex")?.name, "Codex CLI")
        XCTAssertEqual(AgentAttribution.match(command: "gemini -p hi")?.name, "Gemini CLI")
        XCTAssertEqual(AgentAttribution.match(command: "/usr/local/bin/aider --model x")?.name, "Aider")
    }

    func testAppBundlesAreEditorTerminals() {
        let cursor = AgentAttribution.match(command: "/Applications/Cursor.app/Contents/MacOS/Cursor")
        XCTAssertEqual(cursor?.name, "Cursor")
        XCTAssertEqual(cursor?.confidence, .editorTerminal)
        XCTAssertEqual(AgentAttribution.match(command: "/Applications/Visual Studio Code.app/Contents/MacOS/Code")?.name, "VS Code")
        XCTAssertEqual(AgentAttribution.match(command: "/Applications/Windsurf.app/Contents/MacOS/Windsurf")?.name, "Windsurf")
    }

    func testKernelNameWinsOverSpacedPath() {
        let path = "/Users/me/Library/Application Support/Claude/claude-code/2.1.0/claude.app/Contents/MacOS/claude --flag"
        XCTAssertEqual(AgentAttribution.match(command: path, executableName: "claude")?.name, "Claude Code")
        XCTAssertNil(AgentAttribution.match(command: path))
    }

    func testDesktopAppIsNotTheCli() {
        XCTAssertNil(AgentAttribution.match(command: "/Applications/Claude.app/Contents/MacOS/Claude", executableName: "Claude"))
    }

    func testDoesNotMatchProjectFolderNamedClaude() {
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
        XCTAssertTrue(owner?.isLiveAgentSession == true)
    }

    func testListenerItselfIsNeverTheAgent() {
        // An editor helper that listens resolves to the editor above it, so
        // every helper of one window shares one session.
        let t = table([
            (50, 1, "/Applications/Cursor.app/Contents/MacOS/Cursor"),
            (300, 50, "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper.app/Contents/MacOS/Cursor Helper --type=utility"),
        ])
        let owner = AgentAttribution.owner(ofPid: 300, in: t, environmentOf: noEnvironment)
        XCTAssertEqual(owner?.name, "Cursor")
        XCTAssertEqual(owner?.sessionPid, 50)
    }

    func testSessionIsTheCliNotTheDesktopAppAboveIt() {
        let t = table([
            (50, 1, "/Applications/Claude.app/Contents/MacOS/Claude"),
            (100, 50, "claude"),
            (200, 100, "/bin/zsh"),
            (300, 200, "node server.js"),
        ])
        XCTAssertEqual(AgentAttribution.owner(ofPid: 300, in: t, environmentOf: noEnvironment)?.sessionPid, 100)
    }

    func testUnattributedWhenNoAgentAncestorAndNoMarkers() {
        let t = table([(200, 1, "/sbin/launchd"), (300, 200, "node server.js")])
        XCTAssertNil(AgentAttribution.owner(ofPid: 300, in: t, environmentOf: noEnvironment))
    }

    func testStopsAtRootWithoutInfiniteLoop() {
        let t = table([(300, 300, "node server.js")])
        XCTAssertNil(AgentAttribution.owner(ofPid: 300, in: t, environmentOf: noEnvironment))
    }

    // MARK: - Environment markers (survive reparenting)

    func testDetachedServerAttributedByEnvironment() {
        // The shell that started the server is gone: server(300) -> launchd.
        let t = table([(4242, 1, "claude"), (300, 1, "node server.js")])
        let owner = AgentAttribution.owner(ofPid: 300, in: t) { pid in
            pid == 300 ? ["CLAUDECODE": "1", "CLAUDE_PID": "4242"] : [:]
        }
        XCTAssertEqual(owner?.name, "Claude Code")
        XCTAssertEqual(owner?.sessionPid, 4242)
        XCTAssertEqual(owner?.source, .environment)
        XCTAssertFalse(owner?.sessionEnded ?? true)
    }

    func testEndedSessionIsReportedAsEnded() {
        // The agent named by CLAUDE_PID has exited.
        let t = table([(300, 1, "node server.js")])
        let owner = AgentAttribution.owner(ofPid: 300, in: t) { _ in ["CLAUDECODE": "1", "CLAUDE_PID": "1433"] }
        XCTAssertEqual(owner?.name, "Claude Code")
        XCTAssertNil(owner?.sessionPid)
        XCTAssertTrue(owner?.sessionEnded == true)
        XCTAssertFalse(owner?.isLiveAgentSession ?? true)
        XCTAssertEqual(owner?.label, "Claude Code (ended)")
    }

    func testReusedSessionPidIsNotTrusted() {
        let t = table([(1433, 1, "/usr/bin/sleep 100"), (300, 1, "node server.js")])
        let owner = AgentAttribution.owner(ofPid: 300, in: t) { _ in ["CLAUDECODE": "1", "CLAUDE_PID": "1433"] }
        XCTAssertTrue(owner?.sessionEnded == true)
    }

    func testAncestryWinsOverEnvironment() {
        let t = table([(100, 1, "claude"), (300, 100, "node server.js")])
        let owner = AgentAttribution.owner(ofPid: 300, in: t) { _ in ["CLAUDECODE": "1", "CLAUDE_PID": "999"] }
        XCTAssertEqual(owner?.sessionPid, 100)
        XCTAssertEqual(owner?.source, .processTree)
    }

    func testTerminalAgentOutranksEditorMarker() {
        let env = ["CLAUDECODE": "1", "CURSOR_TRACE_ID": "abc", "TERM_PROGRAM": "vscode"]
        XCTAssertEqual(AgentAttribution.ownerFromEnvironment(env, in: .empty)?.name, "Claude Code")
    }

    func testEditorMarkersAreTerminalsNotAgents() {
        let cursor = AgentAttribution.ownerFromEnvironment(["CURSOR_TRACE_ID": "x", "TERM_PROGRAM": "vscode"], in: .empty)
        XCTAssertEqual(cursor?.name, "Cursor")
        XCTAssertEqual(cursor?.confidence, .editorTerminal)
        XCTAssertEqual(AgentAttribution.ownerFromEnvironment(["TERM_PROGRAM": "vscode"], in: .empty)?.name, "VS Code")
        XCTAssertNil(AgentAttribution.ownerFromEnvironment(["TERM_PROGRAM": "iTerm.app"], in: .empty))
    }

    func testCursorAgentMarkerIsAnAgent() {
        let owner = AgentAttribution.ownerFromEnvironment(["CURSOR_AGENT": "1", "CURSOR_TRACE_ID": "x"], in: .empty)
        XCTAssertEqual(owner?.name, "Cursor")
        XCTAssertEqual(owner?.confidence, .agent)
    }

    func testVSCodeForkResolvedFromAskpassPath() {
        let env = ["TERM_PROGRAM": "vscode", "VSCODE_GIT_ASKPASS_MAIN": "/Applications/Windsurf.app/Contents/Resources/app/extensions/git/dist/askpass-main.js"]
        let owner = AgentAttribution.ownerFromEnvironment(env, in: .empty)
        XCTAssertEqual(owner?.name, "Windsurf")
        XCTAssertEqual(owner?.confidence, .editorTerminal)
    }

    func testDeclaredOwnerInEnvironmentLabelsChildren() {
        let owner = AgentAttribution.ownerFromEnvironment(["PORTKILLA_OWNER": "claude-code", "TERM_PROGRAM": "vscode"], in: .empty)
        XCTAssertEqual(owner?.name, "Claude Code")
        XCTAssertEqual(owner?.source, .declared)
        XCTAssertEqual(owner?.confidence, .agent)
    }

    func testSessionPidIgnoredWhenNotNumeric() {
        let owner = AgentAttribution.ownerFromEnvironment(["CLAUDECODE": "1", "CLAUDE_PID": "nope"], in: .empty)
        XCTAssertEqual(owner?.name, "Claude Code")
        XCTAssertNil(owner?.sessionPid)
        XCTAssertFalse(owner?.sessionEnded ?? true)
    }

    func testOnlyAllowlistedKeysAreRequested() {
        XCTAssertEqual(AgentSignatures.markerKeys, [
            "CLAUDECODE", "CURSOR_AGENT", "GEMINI_CLI", "CODEX_SANDBOX", "CODEX_SANDBOX_NETWORK_DISABLED",
            "CURSOR_TRACE_ID", "TERM_PROGRAM", "PORTKILLA_OWNER", "CLAUDE_PID",
            "VSCODE_GIT_ASKPASS_MAIN", "VSCODE_GIT_ASKPASS_NODE",
        ])
    }

    // MARK: - Names people type

    func testCanonicalNames() {
        XCTAssertEqual(AgentSignatures.canonicalName("claude"), "Claude Code")
        XCTAssertEqual(AgentSignatures.canonicalName("Claude-Code"), "Claude Code")
        XCTAssertEqual(AgentSignatures.canonicalName(" vscode\n"), "VS Code")
        XCTAssertEqual(AgentSignatures.canonicalName("my-bot"), "my-bot")
        XCTAssertEqual(AgentSignatures.canonicalName("evil\nline"), "evil line")
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

    func testCallerFallsBackToOwnEnvironmentWithLivenessCheck() {
        let t = table([(77, 1, "claude"), (300, 1, "portkilla kill 3000")])
        let live = AgentAttribution.callerOwner(callerPid: 300, in: t, environment: ["CLAUDECODE": "1", "CLAUDE_PID": "77"])
        XCTAssertEqual(live?.sessionPid, 77)

        let stale = AgentAttribution.callerOwner(callerPid: 300, in: t, environment: ["CLAUDECODE": "1", "CLAUDE_PID": "78"])
        XCTAssertEqual(stale?.name, "Claude Code")
        XCTAssertNil(stale?.sessionPid, "a stale CLAUDE_PID must not pin the caller to a dead session")
    }
}
