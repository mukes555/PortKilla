import XCTest
import SwiftUI
import AppKit
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

    // MARK: - Bugs the coverage pass found

    func testALoneMarkerIsRefusedRatherThanDuplicated() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("portnanny-audit-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        try "# Rules\n\n\(AgentDocsInstaller.beginMarker)\nmy own notes\n".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try AgentDocsInstaller.install(into: file)) { error in
            guard case AgentDocsInstaller.InstallError.danglingMarker = error else { return XCTFail("expected a dangling marker error, got \(error)") }
        }
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("my own notes"), "nothing the person wrote is touched")
        XCTAssertEqual(text.components(separatedBy: AgentDocsInstaller.beginMarker).count, 2, "and no second block is appended")
    }

    func testListFiltersAreAlternativesNotASet() {
        for combination in [["--mine", "--orphaned"], ["--unowned", "--agent", "Cursor"], ["--mine", "--unowned"]] {
            XCTAssertEqual(CLIArguments.parse(["list"] + combination), .failure(.conflictingTargets), combination.joined(separator: " "))
        }
        guard case .success(.list(let allowed)) = CLIArguments.parse(["list", "--mine", "--json"]) else {
            return XCTFail("--json is not a filter and must still parse alongside one")
        }
        XCTAssertTrue(allowed.mine)
        XCTAssertTrue(allowed.json)
    }

    func testAnExplicitRangeSurvivesPrefer() {
        guard case .success(.exec(let typed)) = CLIArguments.parse(["exec", "--range", "3000-3999", "--prefer", "3500", "--", "npm"]) else {
            return XCTFail("expected exec options")
        }
        XCTAssertEqual(typed.range, 3000...3999, "the range the caller typed is the range they get")
        XCTAssertEqual(typed.prefer, 3500)

        guard case .success(.exec(let shifted)) = CLIArguments.parse(["exec", "--prefer", "5000", "--", "npm"]) else {
            return XCTFail("expected exec options")
        }
        XCTAssertEqual(shifted.range, 5000...5999, "prefer alone still shifts the default window")
    }

    // MARK: - The detail sheet's way out

    @MainActor
    func testTheDetailSheetDrawsItsCloseButton() throws {
        // The bar used to be three fake traffic lights; the only real one had
        // no name and no keyboard path. It must still draw something.
        let view = NSHostingView(rootView: DetailTitleBar(onClose: {}))
        view.frame = NSRect(x: 0, y: 0, width: 120, height: 30)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        var drawnPixels = 0
        for x in 0..<bitmap.pixelsWide where drawnPixels == 0 {
            for y in 0..<bitmap.pixelsHigh {
                if let colour = bitmap.colorAt(x: x, y: y), colour.alphaComponent > 0.1 {
                    drawnPixels += 1
                    break
                }
            }
        }
        XCTAssertGreaterThan(drawnPixels, 0, "the close button drew nothing")
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
