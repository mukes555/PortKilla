import XCTest
@testable import PortNannyCore
@testable import PortNanny

/// One test per defect the 2026-09 audit confirmed, so none of them can
/// come back quietly.
final class AuditFixesTests: XCTestCase {

    // MARK: - Correctness

    func testAncestryKeepsWalkingAfterAChainEnds() {
        // The session pid's chain ends at launchd (ppid 0). The caller's own
        // chain is still in the queue and must be walked too.
        let table = ProcessTable.ancestry(of: Int(getpid()), including: [1])
        XCTAssertTrue(table.entries.contains { $0.pid == Int(getpid()) }, "the caller is in its own ancestry")
        XCTAssertTrue(table.entries.contains { $0.pid == Int(getppid()) }, "and so is its parent")
    }

    func testASupervisorsRespawnCountsAsANewOccupant() {
        let before = [3000: PortManager.occupantIdentity(pid: 100, name: "node")]
        let after = [3000: PortManager.occupantIdentity(pid: 200, name: "node")]
        let events = PortManager.watchEvents(watched: [3000], previous: before, current: after)
        XCTAssertEqual(events.count, 1, "same name, new pid: the guard must see it")
        guard case .occupied(let name)? = events.first?.kind else { return XCTFail("expected an occupied event") }
        XCTAssertEqual(name, "node", "the pid is how it is remembered, not how it is shown")

        let unchanged = PortManager.watchEvents(watched: [3000], previous: before, current: before)
        XCTAssertTrue(unchanged.isEmpty, "the same process is not an event")
    }

    func testWaitWithNoTimeoutStillAnswers() {
        let free = ManagedRuntime.waitForPortsFree([65010], timeout: 0)
        XCTAssertTrue(free.isEmpty, "a free port is free even when the caller will not wait")
    }

    func testAProjectAppearingAfterALightScanRepublishes() {
        let light = PortInfo(port: 3000, pid: 1, processName: "node", command: "node", user: "dev",
                             memoryUsage: "1MB", memorySizeKB: 1024, type: .nodejs)
        let full = PortInfo(port: 3000, pid: 1, processName: "node", command: "node", user: "dev",
                            memoryUsage: "1MB", memorySizeKB: 1024, type: .nodejs,
                            projectName: "api", projectPath: "/Users/dev/code/api")
        XCTAssertNotEqual(PortManager.stableSignature([light]), PortManager.stableSignature([full]),
                          "the row would otherwise keep the light scan's missing project")
        XCTAssertEqual(PortManager.stableSignature([light], depth: .light), PortManager.stableSignature([full], depth: .light),
                       "a light scan never knows the project, so it cannot be part of its signature")
    }

    func testACallerWithoutASessionKeyBorrowsItsPidLikeExecDoes() {
        let processes = ProcessTable(entries: [
            ProcessTable.Entry(pid: 845, ppid: 1, rssKB: 0, cpuPercent: 0, ageSeconds: nil, command: "codex", processName: "codex", uid: getuid()),
            ProcessTable.Entry(pid: 900, ppid: 845, rssKB: 0, cpuPercent: 0, ageSeconds: nil, command: "portnanny kill 3000", processName: "portnanny", uid: getuid()),
        ])
        let caller = AgentAttribution.callerOwner(callerPid: 900, in: processes, environment: [:])
        XCTAssertEqual(caller?.name, "Codex CLI")
        XCTAssertEqual(caller?.sessionKey, "845", "exec stamps the same value on the servers it starts")
        let detached = AgentOwner(name: "Codex CLI", sessionKey: "845", source: .declared)
        XCTAssertEqual(KillDecision.forAgent(caller: caller, target: detached), .allow, "its own session may stop its own server")
    }

    // MARK: - Security

    func testChildCommandsAreRedactedLikeTheirParent() {
        let table = ProcessTable(entries: [
            ProcessTable.Entry(pid: 100, ppid: 1, rssKB: 0, cpuPercent: 0, ageSeconds: nil,
                               command: "node server.js", processName: "node", uid: 0),
            ProcessTable.Entry(pid: 101, ppid: 100, rssKB: 0, cpuPercent: 0, ageSeconds: nil,
                               command: "node worker.js --token=sk-secret-1", processName: "node", uid: 0),
        ], listeners: [NativeScanner.Listener(pid: 100, port: 3000, host: "127.0.0.1", proto: "tcp", connections: 0)])
        let ports = (try? PortScanner().scanActivePorts(processes: table, depth: .full)) ?? []
        let children = ports.first?.children ?? []
        XCTAssertFalse(children.isEmpty, "the worker is a child of the listener")
        for child in children {
            XCTAssertFalse(child.command.contains("sk-secret-1"), child.command)
        }
    }
}
