import XCTest
@testable import PortKillaCore
@testable import PortKilla

/// Regression tests for the v1.11.0 performance batch.
final class PerformanceFixesTests: XCTestCase {

    // MARK: - Per-process facts are read once per (pid, start time)

    func testFactsAreReadOncePerProcessLifetime() {
        var pathReads = 0
        var commandReads = 0
        let cache = ProcessFacts(
            readPath: { _ in pathReads += 1; return "/bin/node" },
            readCommand: { _ in commandReads += 1; return "node server.js" },
            readMarkers: { _, _ in [:] }
        )

        let first = cache.facts(for: 42, startedAt: 1000, shortName: "node")
        let again = cache.facts(for: 42, startedAt: 1000, shortName: "node")
        XCTAssertEqual(first, again)
        XCTAssertEqual(pathReads, 1)
        XCTAssertEqual(commandReads, 1)

        // Same pid, new start time: a recycled pid is a different process.
        _ = cache.facts(for: 42, startedAt: 2000, shortName: "node")
        XCTAssertEqual(pathReads, 2)

        // Same pid and start time, new kernel name: exec without fork
        // (sh -c 'exec node …') must not keep serving the shell's facts.
        _ = cache.facts(for: 42, startedAt: 2000, shortName: "sh")
        XCTAssertEqual(pathReads, 3)

        cache.prune(keeping: [])
        XCTAssertEqual(cache.count, 0)
    }

    func testMarkersAreCachedWithTheFacts() {
        var markerReads = 0
        let cache = ProcessFacts(
            readPath: { _ in nil },
            readCommand: { _ in nil },
            readMarkers: { _, _ in markerReads += 1; return ["CLAUDECODE": "1"] }
        )
        _ = cache.facts(for: 7, startedAt: 1, shortName: "node")
        XCTAssertEqual(cache.markers(for: 7, keys: ["CLAUDECODE"]), ["CLAUDECODE": "1"])
        XCTAssertEqual(cache.markers(for: 7, keys: ["CLAUDECODE"]), ["CLAUDECODE": "1"])
        XCTAssertEqual(markerReads, 1)

        // A pid the cache never captured is read through but not remembered.
        _ = cache.markers(for: 8, keys: ["CLAUDECODE"])
        _ = cache.markers(for: 8, keys: ["CLAUDECODE"])
        XCTAssertEqual(markerReads, 3)
    }

    // MARK: - One native pass yields both table and listeners

    func testCaptureReturnsListenersWithTheTable() throws {
        let table = ProcessTable.capture()
        let listeners = try XCTUnwrap(table.listeners, "native capture should carry listeners")
        XCTAssertFalse(table.allEntries.isEmpty)
        XCTAssertEqual(table.uid(for: Int(getpid())), getuid())
        _ = listeners // may legitimately be empty on a quiet machine
    }

    func testAncestryTableContainsOurChainOnly() {
        let table = ProcessTable.ancestry(of: Int(getpid()))
        XCTAssertNotNil(table.command(for: Int(getpid())))
        XCTAssertEqual(table.ppid(for: Int(getpid())), Int(getppid()))
        XCTAssertLessThan(table.allEntries.count, 64)
    }

    // MARK: - Docker stays off the hot path

    func testDockerBackoffGrowsAndCaps() {
        XCTAssertEqual(DockerService.nextBackoff(after: 0), 5)
        XCTAssertEqual(DockerService.nextBackoff(after: 5), 10)
        XCTAssertEqual(DockerService.nextBackoff(after: 40), 60)
        XCTAssertEqual(DockerService.nextBackoff(after: 60), 60)
    }

    // MARK: - Publish gates

    private func port(_ number: Int, container: String? = nil, owner: AgentOwner? = nil) -> PortInfo {
        PortInfo(port: number, pid: 1, processName: "node", command: "node", user: "me", memoryUsage: "1MB",
                 memorySizeKB: 1024, type: .nodejs, containerName: container, agentOwner: owner)
    }

    func testLightSignatureIgnoresEnrichmentAndFullDoesNot() {
        let bare = [port(3000)]
        let enriched = [port(3000, container: "db", owner: AgentOwner(name: "Cursor", source: .environment))]
        XCTAssertEqual(PortManager.stableSignature(bare, depth: .light), PortManager.stableSignature(enriched, depth: .light))
        XCTAssertNotEqual(PortManager.stableSignature(bare, depth: .full), PortManager.stableSignature(enriched, depth: .full))
    }

    func testVisiblePortsAreCachedAndFollowTheSetting() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        let mine = PortInfo(port: 3000, pid: 1, processName: "node", command: "/Users/me/node", user: NSUserName(),
                            memoryUsage: "", memorySizeKB: 0, type: .nodejs)
        let daemon = PortInfo(port: 5353, pid: 2, processName: "mDNSResponder", command: "/usr/sbin/mDNSResponder",
                              user: "root", memoryUsage: "", memorySizeKB: 0, type: .other)
        manager.activePorts = [mine, daemon]
        manager.hideSystemProcesses = true
        XCTAssertEqual(manager.visiblePorts.map(\.port), [3000])
        XCTAssertEqual(manager.hiddenPortsCount, 1)
        XCTAssertEqual(manager.menuBarBadgeCount, 1)
        manager.hideSystemProcesses = false
        XCTAssertEqual(manager.visiblePorts.map(\.port), [3000, 5353])
    }

    func testGuardedOccupantsAreAttributedEvenOnLightScans() {
        // server(300) on :3000 under claude(100); a light scan left agentOwner nil.
        let rows = [(100, 1, "claude"), (200, 100, "/bin/zsh"), (300, 200, "node server.js")]
        let lines = rows.map { "\($0.0) \($0.1) 1024 0.0 05:00 \($0.2)" }.joined(separator: "\n")
        let table = ProcessTable(psOutput: lines)
        let occupant = PortInfo(port: 3000, pid: 300, processName: "node", command: "node server.js", user: "me",
                                memoryUsage: "", memorySizeKB: 0, type: .nodejs)

        let owners = PortManager.ownersOfGuardedOccupants([3000], in: [occupant, port(4000)], processes: table)
        XCTAssertEqual(owners[300]?.name, "Claude Code", "keyed by the occupant's pid")
        XCTAssertNil(owners[1], "only guarded ports are attributed")
    }

    func testTestsSignatureIgnoresCPU() {
        let a = TestProcessInfo(pid: 1, processName: "vitest", command: "vitest", memoryUsage: "", memorySizeKB: 0, cpuPercent: 1, type: .vitest)
        let b = TestProcessInfo(pid: 1, processName: "vitest", command: "vitest", memoryUsage: "", memorySizeKB: 0, cpuPercent: 90, type: .vitest)
        XCTAssertEqual(PortManager.testsSignature([a]), PortManager.testsSignature([b]))
    }
}
