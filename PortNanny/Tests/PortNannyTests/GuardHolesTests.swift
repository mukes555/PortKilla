import XCTest
@testable import PortNannyCore
@testable import PortNanny

/// Regression tests for the guard holes found by the post-batch audit.
final class GuardHolesTests: XCTestCase {

    private func table(_ rows: [(Int, Int, String)]) -> ProcessTable {
        let lines = rows.map { "\($0.0) \($0.1) 1024 0.0 05:00 \($0.2)" }.joined(separator: "\n")
        return ProcessTable(psOutput: lines)
    }

    // MARK: - Session identity

    func testSessionKeyBeatsPidForIdentity() {
        let a = AgentOwner(name: "Claude Code", sessionPid: 10, sessionKey: "abc", source: .processTree)
        let restartedSamePid = AgentOwner(name: "Claude Code", sessionPid: 10, sessionKey: "xyz", source: .environment)
        let samePidNoKey = AgentOwner(name: "Claude Code", sessionPid: 10, source: .environment)
        XCTAssertEqual(a.isSameSession(as: restartedSamePid), false)
        XCTAssertEqual(a.isSameSession(as: samePidNoKey), true, "falls back to pids when a key is missing")
        XCTAssertNil(AgentOwner(name: "Cursor", source: .environment).isSameSession(as: a))
        if case .refuse = KillDecision.forAgent(caller: a, target: restartedSamePid) {} else {
            XCTFail("different session keys on the same pid must refuse")
        }
    }

    func testClaudeSessionIdIsReadFromTheEnvironment() {
        let t = table([(4242, 1, "claude"), (300, 1, "node server.js")])
        let owner = AgentAttribution.owner(ofPid: 300, in: t) { _ in
            ["CLAUDECODE": "1", "CLAUDE_PID": "4242", "CLAUDE_CODE_SESSION_ID": "11111111-2222"]
        }
        XCTAssertEqual(owner?.sessionKey, "11111111-2222")
        XCTAssertEqual(owner?.sessionId, "Claude Code@11111111-2222", "a short key is shown whole")
        let uuid = AgentOwner(name: "Claude Code", sessionKey: "3f2a9c1d-0000-4000-8000-000000000000", source: .environment)
        XCTAssertEqual(uuid.sessionId, "Claude Code@3f2a9c1d", "a UUID is shortened")
    }

    // MARK: - Pid reuse by a different agent

    func testSessionPidReusedByAnotherAgentIsNotTrusted() {
        let t = table([(4242, 1, "codex"), (300, 1, "node server.js")])
        let owner = AgentAttribution.owner(ofPid: 300, in: t) { _ in ["CLAUDECODE": "1", "CLAUDE_PID": "4242"] }
        XCTAssertEqual(owner?.name, "Claude Code")
        XCTAssertTrue(owner?.sessionEnded == true, "pid 4242 is Codex now, not the Claude session that started this")
    }

    // MARK: - Markerless sessions expire

    func testMarkerWithoutSessionEndsWhenNoSuchAgentRuns() {
        let nobody = table([(300, 1, "node server.js")])
        let ended = AgentAttribution.owner(ofPid: 300, in: nobody) { _ in ["CURSOR_AGENT": "1"] }
        XCTAssertTrue(ended?.sessionEnded == true)
        XCTAssertEqual(KillDecision.forAgent(caller: AgentOwner(name: "Claude Code", sessionPid: 1, source: .processTree), target: ended), .allow)

        let cursorRunning = table([(50, 1, "/Applications/Cursor.app/Contents/MacOS/Cursor"), (300, 1, "node server.js")])
        let live = AgentAttribution.owner(ofPid: 300, in: cursorRunning) { _ in ["CURSOR_AGENT": "1"] }
        XCTAssertFalse(live?.sessionEnded ?? true, "Cursor is still running somewhere")
    }

    func testDeclaredOwnersNeverExpireByLiveness() {
        let nobody = table([(300, 1, "node server.js")])
        let declared = AgentAttribution.owner(ofPid: 300, in: nobody) { _ in ["PORTNANNY_OWNER": "my-bot"] }
        XCTAssertFalse(declared?.sessionEnded ?? true)
    }

    // MARK: - tmux is an attribution barrier

    func testMarkersThroughTmuxKeepTheNameButNotTheSession() {
        // claude(100) started the tmux server(150); a pane shell(200) started server(300).
        let t = table([
            (100, 1, "claude"),
            (150, 1, "/opt/homebrew/bin/tmux"),
            (200, 150, "/bin/zsh"),
            (300, 200, "node server.js"),
        ])
        let owner = AgentAttribution.owner(ofPid: 300, in: t) { _ in ["CLAUDECODE": "1", "CLAUDE_PID": "100", "CLAUDE_CODE_SESSION_ID": "k"] }
        XCTAssertEqual(owner?.name, "Claude Code")
        XCTAssertNil(owner?.sessionPid)
        XCTAssertNil(owner?.sessionKey)
        XCTAssertNil(AgentAttribution.ownerFromAncestry(ofPid: 300, in: t), "the tree stops at the multiplexer")
    }

    // MARK: - Verdicts

    func testVerdictsDistinguishClearedFromNotChecked() {
        let live = AgentOwner(name: "Claude Code", sessionPid: 5, source: .processTree)
        let cursor = AgentOwner(name: "Cursor", sessionPid: 6, source: .processTree)
        XCTAssertEqual(KillDecision.verdict(caller: nil, target: live, forced: false), "not-evaluated: caller unknown")
        XCTAssertEqual(KillDecision.verdict(caller: cursor, target: nil, forced: false), "refused")
        XCTAssertEqual(KillDecision.verdict(caller: nil, target: nil, forced: false), "not-evaluated: target unknown")
        XCTAssertEqual(KillDecision.verdict(caller: cursor, target: live, forced: false), "refused")
        XCTAssertEqual(KillDecision.verdict(caller: cursor, target: live, forced: true), "overridden")
        XCTAssertEqual(KillDecision.verdict(caller: live, target: live, forced: false), "allowed")
    }

    // MARK: - --mine agrees with the guard

    func testMineMatchesWhatKillWouldAllow() {
        let me = AgentOwner(name: "Claude Code", sessionPid: 7, source: .processTree)
        let otherSession = AgentOwner(name: "Claude Code", sessionPid: 9, source: .processTree)
        let ports = [
            PortInfo(port: 1, pid: 1, processName: "a", command: "", user: "", memoryUsage: "", memorySizeKB: 0, type: .nodejs, agentOwner: me),
            PortInfo(port: 2, pid: 2, processName: "b", command: "", user: "", memoryUsage: "", memorySizeKB: 0, type: .nodejs, agentOwner: otherSession),
        ]
        var options = CLICommand.ListOptions()
        options.mine = true
        XCTAssertEqual(PortNannyCLI.filtered(ports, by: options, caller: me).map(\.port), [1])
        let terminal = AgentOwner(name: "Cursor", source: .environment, confidence: .editorTerminal)
        let claudePort = PortInfo(port: 3, pid: 3, processName: "c", command: "", user: "", memoryUsage: "", memorySizeKB: 0, type: .nodejs,
                                  agentOwner: AgentOwner(name: "Claude Code", sessionPid: 8, source: .processTree))
        XCTAssertEqual(PortNannyCLI.filtered([claudePort], by: options, caller: terminal).map(\.port), [],
                       "a Cursor terminal may not stop Claude Code's server, so it is not 'mine'")
    }

    // MARK: - New commands parse

    func testFreeWaitOpenHistoryParsing() {
        var free = CLICommand.KillOptions()
        free.port = 3000
        free.freeIsSuccess = true
        XCTAssertEqual(CLIArguments.parse(["free", "3000"]), .success(.kill(free)))
        XCTAssertEqual(CLIArguments.parse(["wait", "3000"]), .success(.wait(port: 3000, timeout: 30, json: false)))
        XCTAssertEqual(CLIArguments.parse(["wait", "3000", "--timeout=5", "--json"]), .success(.wait(port: 3000, timeout: 5, json: true)))
        XCTAssertEqual(CLIArguments.parse(["wait"]), .failure(.missingTarget))
        XCTAssertEqual(CLIArguments.parse(["open", "3000"]), .success(.open(port: 3000)))
        var history = CLICommand.HistoryOptions()
        history.port = 3000
        history.json = true
        XCTAssertEqual(CLIArguments.parse(["history", "--json", "--port", "3000"]), .success(.history(history)))
        XCTAssertEqual(CLIArguments.parse(["history", "--since", "1h"]), .failure(.unknownOption("--since", command: "history")))
    }

    // MARK: - JSON contract

    func testJSONKeySetsAreStable() throws {
        // Scripts parse these; a rename is a break.
        let owner = AgentOwner(name: "Claude Code", sessionPid: 1, sessionKey: "k", source: .processTree)
        let port = PortInfo(port: 3000, pid: 1, processName: "node", command: "node", user: "me", memoryUsage: "1MB",
                            memorySizeKB: 1024, type: .nodejs, agentOwner: owner)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(port)) as? [String: Any])
        // Optionals that are nil are omitted, so these are the always-present keys.
        XCTAssertEqual(Set(json.keys.map { $0 }), [
            "port", "pid", "processName", "command", "user", "memoryUsage", "memorySizeKB", "type", "proto", "cpuPercent", "agentOwner",
            "connections",
        ])
        let ownerJSON = try XCTUnwrap(json["agentOwner"] as? [String: Any])
        XCTAssertEqual(Set(ownerJSON.keys.map { $0 }), ["name", "sessionPid", "sessionKey", "source", "confidence", "sessionEnded"])
    }

    func testAgentDocsMentionWhatAgentsNeed() {
        for needle in ["exit code 3", "stderr", "--dry-run", "PORTNANNY_OWNER", "free", "wait", "history", "--pid"] {
            XCTAssertTrue(PortNannyCLI.agentDocs.lowercased().contains(needle.lowercased()), "agent-docs should mention \(needle)")
        }
    }
}
