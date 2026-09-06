import XCTest
@testable import PortKilla

final class CLIArgumentsTests: XCTestCase {

    private func parse(_ args: String) -> Result<CLICommand, CLIArguments.ParseError>? {
        CLIArguments.parse(args.split(separator: " ").map(String.init))
    }

    func testNoArgumentsOrLaunchFlagsMeanGUI() {
        XCTAssertNil(CLIArguments.parse([]))
        XCTAssertNil(parse("-psn_0_12345"))
        XCTAssertNil(parse("-NSDocumentRevisionsDebugMode YES"))
    }

    func testTypoIsAnErrorNotTheGUI() {
        XCTAssertEqual(parse("kil 3000"), .failure(.unknownCommand("kil")))
    }

    func testKillParsing() {
        var expected = CLICommand.KillOptions()
        expected.port = 3000
        XCTAssertEqual(parse("kill 3000"), .success(.kill(expected)))

        expected.force = true; expected.dryRun = true; expected.json = true
        XCTAssertEqual(parse("kill 3000 --force --dry-run --json"), .success(.kill(expected)))
        XCTAssertEqual(parse("kill -9 3000 --dry-run --json"), .success(.kill(expected)))

        var byPid = CLICommand.KillOptions()
        byPid.pid = 42
        XCTAssertEqual(parse("kill --pid 42"), .success(.kill(byPid)))
        XCTAssertEqual(parse("kill --pid=42"), .success(.kill(byPid)))
    }

    func testKillRejectsWhatItDoesNotUnderstand() {
        // An ignored flag on a kill is the worst possible failure mode.
        XCTAssertEqual(parse("kill 3000 --dry-rum"), .failure(.unknownOption("--dry-rum", command: "kill")))
        XCTAssertEqual(parse("kill"), .failure(.missingTarget))
        XCTAssertEqual(parse("kill 3000 4000"), .failure(.tooManyTargets))
        XCTAssertEqual(parse("kill abc"), .failure(.invalidNumber("abc", option: "port")))
        XCTAssertEqual(parse("kill --pid"), .failure(.missingValue("--pid")))
        XCTAssertEqual(parse("kill --pid x"), .failure(.invalidNumber("x", option: "--pid")))
        XCTAssertEqual(parse("kill 0"), .failure(.invalidNumber("0", option: "port")))
        XCTAssertEqual(parse("kill 99999"), .failure(.invalidNumber("99999", option: "port")))
        XCTAssertEqual(parse("kill 3000 --pid 42"), .failure(.conflictingTargets))
    }

    func testListParsing() {
        var options = CLICommand.ListOptions()
        XCTAssertEqual(parse("list"), .success(.list(options)))
        options.json = true; options.mine = true
        XCTAssertEqual(parse("list --json --mine"), .success(.list(options)))

        var byAgent = CLICommand.ListOptions()
        byAgent.agent = "Cursor"
        XCTAssertEqual(parse("list --agent Cursor"), .success(.list(byAgent)))
        XCTAssertEqual(parse("list --agent=Cursor"), .success(.list(byAgent)))
        XCTAssertEqual(parse("list --agent"), .failure(.missingValue("--agent")))
        XCTAssertEqual(parse("list --all"), .failure(.unknownOption("--all", command: "list")))
    }

    func testOtherCommands() {
        XCTAssertEqual(parse("whoami --json"), .success(.whoami(json: true)))
        XCTAssertEqual(parse("whoami --yaml"), .failure(.unknownOption("--yaml", command: "whoami")))
        XCTAssertEqual(parse("version"), .success(.version(json: false)))
        XCTAssertEqual(parse("--version"), .success(.version(json: false)))
        XCTAssertEqual(parse("help"), .success(.help(topic: nil)))
        XCTAssertEqual(parse("-h"), .success(.help(topic: nil)))
        XCTAssertEqual(parse("agent-docs"), .success(.agentDocs))
    }

    func testUsageDocumentsEveryExitCode() {
        for code in ["0 done", "1 nothing listening", "2 usage", "3 refused", "4 kill failed", "5 still running"] {
            XCTAssertTrue(CLIArguments.usage.contains(code), "usage should document exit code \(code)")
        }
    }

    // MARK: - Target selection

    private func port(_ number: Int, pid: Int, proto: String = "tcp") -> PortInfo {
        PortInfo(port: number, pid: pid, processName: "node", command: "node", user: "me",
                 memoryUsage: "1MB", memorySizeKB: 1024, type: .nodejs, proto: proto)
    }

    func testKillSelectsEveryProcessOnThePortOnce() {
        let ports = [port(3000, pid: 1), port(3000, pid: 1, proto: "udp"), port(3000, pid: 2), port(3001, pid: 3)]
        var options = CLICommand.KillOptions()
        options.port = 3000
        XCTAssertEqual(CLIKill.select(from: ports, options: options).map(\.pid), [1, 2])

        options = CLICommand.KillOptions()
        options.pid = 2
        XCTAssertEqual(CLIKill.select(from: ports, options: options).map(\.pid), [2])
    }

    func testListFilters() {
        let mine = AgentOwner(name: "Claude Code", sessionPid: 7, source: .processTree)
        let other = AgentOwner(name: "Claude Code", sessionPid: 9, source: .processTree)
        let ended = AgentOwner(name: "Cursor", source: .environment, sessionEnded: true)
        let ports = [
            PortInfo(port: 1, pid: 1, processName: "a", command: "", user: "", memoryUsage: "", memorySizeKB: 0, type: .nodejs, agentOwner: mine),
            PortInfo(port: 2, pid: 2, processName: "b", command: "", user: "", memoryUsage: "", memorySizeKB: 0, type: .nodejs, agentOwner: other),
            PortInfo(port: 3, pid: 3, processName: "c", command: "", user: "", memoryUsage: "", memorySizeKB: 0, type: .nodejs, agentOwner: ended),
            PortInfo(port: 4, pid: 4, processName: "d", command: "", user: "", memoryUsage: "", memorySizeKB: 0, type: .nodejs),
        ]
        var options = CLICommand.ListOptions()
        options.mine = true
        XCTAssertEqual(PortKillaCLI.filtered(ports, by: options, caller: mine).map(\.port), [1])
        options = CLICommand.ListOptions(); options.unowned = true
        XCTAssertEqual(PortKillaCLI.filtered(ports, by: options, caller: nil).map(\.port), [4])
        options = CLICommand.ListOptions(); options.orphaned = true
        XCTAssertEqual(PortKillaCLI.filtered(ports, by: options, caller: nil).map(\.port), [3])
        options = CLICommand.ListOptions(); options.agent = "claude"
        XCTAssertEqual(PortKillaCLI.filtered(ports, by: options, caller: nil).map(\.port), [1, 2])
    }
}
