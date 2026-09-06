import XCTest
@testable import PortKillaCore
@testable import PortKilla

final class KillDecisionTests: XCTestCase {

    private func agent(_ name: String, session: Int? = nil, ended: Bool = false) -> AgentOwner {
        AgentOwner(name: name, sessionPid: session, source: .processTree, confidence: .agent, sessionEnded: ended)
    }

    private func terminal(_ name: String) -> AgentOwner {
        AgentOwner(name: name, source: .environment, confidence: .editorTerminal)
    }

    // MARK: - Agents (CLI)

    func testDifferentAgentsAreRefused() {
        if case .refuse = KillDecision.forAgent(caller: agent("Cursor", session: 10), target: agent("Claude Code", session: 20)) {} else {
            XCTFail("expected refusal")
        }
    }

    func testSameAgentDifferentLiveSessionIsRefused() {
        if case .refuse = KillDecision.forAgent(caller: agent("Claude Code", session: 10), target: agent("Claude Code", session: 99)) {} else {
            XCTFail("expected refusal")
        }
    }

    func testSameSessionIsAllowed() {
        XCTAssertEqual(KillDecision.forAgent(caller: agent("Claude Code", session: 10), target: agent("Claude Code", session: 10)), .allow)
    }

    func testUnknownCallerNeverBlocks() {
        XCTAssertEqual(KillDecision.forAgent(caller: nil, target: agent("Claude Code", session: 10)), .allow)
        XCTAssertEqual(KillDecision.forAgent(caller: nil, target: nil), .allow)
    }

    func testAgentMayNotKillWhatNobodyClaims() {
        // Most unattributed servers are a person's; the agent can ask.
        if case .refuse(let reason) = KillDecision.forAgent(caller: agent("Claude Code", session: 10), target: nil) {
            XCTAssertTrue(reason.contains("not attributed"))
        } else {
            XCTFail("an identified agent must not kill an unattributed server without --force")
        }
        XCTAssertEqual(KillDecision.forAgent(caller: terminal("VS Code"), target: nil), .allow, "a person in an editor terminal is not an agent")
        XCTAssertTrue(KillDecision.forAgent(caller: AgentOwner(name: "my-bot", source: .declared), target: nil).isRefusal, "declared owners are agents")
    }

    func testSameNameUnknownSessionAllowed() {
        let declared = AgentOwner(name: "Claude Code", source: .declared)
        XCTAssertEqual(KillDecision.forAgent(caller: declared, target: agent("Claude Code", session: 55)), .allow)
    }

    func testEndedSessionNeverBlocks() {
        XCTAssertEqual(KillDecision.forAgent(caller: agent("Cursor", session: 1), target: agent("Claude Code", ended: true)), .allow)
    }

    func testEditorTerminalTargetNeverBlocks() {
        // A human's own VS Code terminal must not lock a port against agents.
        XCTAssertEqual(KillDecision.forAgent(caller: agent("Claude Code", session: 1), target: terminal("VS Code")), .allow)
    }

    func testEditorTerminalCallerIsStillRefusedFromAnAgentsServer() {
        if case .refuse = KillDecision.forAgent(caller: terminal("Cursor"), target: agent("Claude Code", session: 20)) {} else {
            XCTFail("a Cursor terminal must not kill Claude Code's live server silently")
        }
    }

    // MARK: - Humans (GUI)

    func testHumanIsWarnedNotRefused() {
        if case .warn(let reason) = KillDecision.forHuman(target: agent("Cursor", session: 812)) {
            XCTAssertTrue(reason.contains("Cursor"))
            XCTAssertTrue(reason.contains("812"))
        } else {
            XCTFail("expected a warning")
        }
        XCTAssertEqual(KillDecision.forHuman(target: agent("Cursor", ended: true)), .allow)
        XCTAssertEqual(KillDecision.forHuman(target: terminal("VS Code")), .allow)
        XCTAssertEqual(KillDecision.forHuman(target: nil), .allow)
    }

    func testLiveAgentNoteCountsOnlyLiveSessions() {
        XCTAssertNil(KillDecision.liveAgentNote(for: [nil, terminal("VS Code"), agent("Cursor", ended: true)]))
        XCTAssertEqual(KillDecision.liveAgentNote(for: [agent("Cursor"), nil]), "1 of these belongs to running AI agent session.")
        XCTAssertEqual(KillDecision.liveAgentNote(for: [agent("Cursor"), agent("Claude Code")]), "2 of these belong to running AI agent sessions.")
    }
}
