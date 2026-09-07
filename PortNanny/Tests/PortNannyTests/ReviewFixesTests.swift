import XCTest
@testable import PortNannyCore

/// Regression tests for the pre-2.0 review: each test names the hole it closes.
final class ReviewFixesTests: XCTestCase {

    private func table(_ rows: [(Int, Int, String)]) -> ProcessTable {
        let lines = rows.map { "\($0.0) \($0.1) 1024 0.0 05:00 \($0.2)" }.joined(separator: "\n")
        return ProcessTable(psOutput: lines)
    }

    private func port(_ number: Int, pid: Int, name: String = "node", owner: AgentOwner? = nil,
                      managedBy: ManagedRuntime? = nil, connections: Int = 0) -> PortInfo {
        PortInfo(port: number, pid: pid, processName: name, command: "\(name) server.js", user: "me", memoryUsage: "1MB",
                 memorySizeKB: 1, type: .nodejs, agentOwner: owner, connections: connections, managedBy: managedBy)
    }

    private func lease(_ port: Int, owner: String, key: String? = nil, pid: Int? = nil, at date: Date = Date()) -> Reservation {
        Reservation(port: port, owner: owner, sessionKey: key, sessionPid: pid, reason: "test", createdAt: date, ttl: 600)
    }

    private var suite = ""
    private var defaults: UserDefaults!
    private var store: ReservationStore!

    override func setUp() {
        suite = "com.mukes555.PortNanny.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        store = ReservationStore(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    // MARK: - Leases

    func testALeaseWithASessionIsNotTakenByNameAlone() throws {
        let holder = AgentOwner(name: "my-bot", sessionKey: "s1", source: .declared)
        let impostor = AgentOwner(name: "my-bot", source: .declared)
        try store.reserve(lease(3000, owner: "my-bot", key: "s1"), by: holder)
        XCTAssertThrowsError(try store.reserve(lease(3000, owner: "my-bot"), by: impostor), "the same name without the session does not renew")
        let held = try XCTUnwrap(store.reservation(for: 3000))
        XCTAssertEqual(store.release(port: 3000, by: impostor), .heldByAnother(held))
        XCTAssertEqual(store.release(port: 3000, by: holder), .released(held))
    }

    func testALeasePinnedToADeadProcessIsOver() throws {
        // exec pins its lease to its own pid, so the lease ends with exec.
        let me = Reservation.currentUser
        XCTAssertTrue(lease(3000, owner: me, pid: 999_999).isOrphaned())
        XCTAssertFalse(lease(3001, owner: me, pid: Int(getpid())).isOrphaned())
        XCTAssertFalse(lease(3002, owner: me).isOrphaned(), "a lease without a pid lives by its clock")
        try store.reserve(lease(3000, owner: me, pid: 999_999), by: nil)
        XCTAssertTrue(store.all().isEmpty, "an orphaned lease is pruned on read")
    }

    func testRecentLeasesAreCachedBrieflyAndRefreshedOnWrite() throws {
        let t0 = Date()
        XCTAssertTrue(store.recent(now: t0).isEmpty)
        let me = AgentOwner(name: "Claude Code", sessionPid: Int(getpid()), sessionKey: "k", source: .processTree)
        try store.reserve(lease(3000, owner: me.name, key: "k", pid: me.sessionPid, at: t0), by: me)
        XCTAssertEqual(store.recent(now: t0).map(\.port), [3000], "a write on this store refreshes its own cache")

        // Another process wrote: this store notices once its cache expires.
        let other = ReservationStore(defaults: defaults)
        try other.reserve(lease(3001, owner: me.name, key: "k", pid: me.sessionPid, at: t0), by: me)
        XCTAssertEqual(store.recent(now: t0.addingTimeInterval(1)).map(\.port), [3000])
        XCTAssertEqual(store.recent(now: t0.addingTimeInterval(ReservationStore.cacheLifetime + 1)).map(\.port), [3000, 3001])
        XCTAssertEqual(store.all(now: t0).map(\.port), [3000, 3001], "all() always reads the file")
    }

    // MARK: - Supervisors

    func testStoppingAReloaderNamesAndJudgesEverythingUnderIt() throws {
        // nodemon(700) supervises the target(812) and a worker(813) that
        // another agent owns; server(900) is unrelated.
        let t = table([(700, 1, "node nodemon"), (812, 700, "node server.js"), (813, 700, "node worker.js"), (900, 1, "node other.js")])
        let reloader = ManagedRuntime(kind: .reloader, name: "nodemon", supervisorPid: 700, supervisorName: "node")
        let claude = AgentOwner(name: "Claude Code", sessionPid: 6, source: .processTree)
        let cursor = AgentOwner(name: "Cursor", sessionPid: 5, source: .processTree)
        let target = port(3000, pid: 812, owner: claude, managedBy: reloader)
        let ports = [target, port(3001, pid: 813, owner: cursor), port(4000, pid: 900)]
        let plan = CLIKill.plan(for: target, force: false, table: t, ports: ports)
        XCTAssertEqual(plan.alsoStops.map(\.port), [3001], "the sibling under the reloader goes too; the unrelated server does not")

        let refusals = CLIKill.refusals(caller: claude, plans: [plan], leases: store, cwd: "/nowhere")
        XCTAssertEqual(refusals.count, 1)
        XCTAssertTrue(refusals[0].contains(":3001 (PID 813), which its supervisor would take down too, is owned by Cursor"), refusals[0])
        let forced = CLIKill.plan(for: target, force: true, table: t, ports: ports)
        XCTAssertTrue(forced.alsoStops.isEmpty, "--force kills the listener itself and takes nothing else")
        XCTAssertTrue(CLIKill.refusals(caller: claude, plans: [forced], leases: store, cwd: "/nowhere").isEmpty)
    }

    func testTheVerdictSaysWhyTheGuardCouldNotJudge() {
        let live = AgentOwner(name: "Claude Code", sessionPid: 5, source: .processTree)
        let mine = [port(3000, pid: 1, owner: live)]
        let nobodys = [port(3000, pid: 1)]
        XCTAssertEqual(CLIKill.verdict(caller: nil, targets: mine, refused: false, forced: false), "not-evaluated: caller unknown")
        XCTAssertEqual(CLIKill.verdict(caller: nil, targets: nobodys, refused: false, forced: false), "not-evaluated: target unknown")
        XCTAssertEqual(CLIKill.verdict(caller: live, targets: nobodys, refused: true, forced: false), "refused")
        XCTAssertEqual(CLIKill.verdict(caller: live, targets: nobodys, refused: true, forced: true), "overridden")
        XCTAssertEqual(CLIKill.verdict(caller: live, targets: mine, refused: false, forced: false), "allowed")
        let terminal = AgentOwner(name: "VS Code", source: .environment, confidence: .editorTerminal)
        XCTAssertEqual(CLIKill.verdict(caller: terminal, targets: nobodys, refused: false, forced: false), "allowed: caller is not an agent")
    }

    func testPM2AppNamesAreValidatedBeforeTheyBecomeArguments() {
        XCTAssertEqual(ManagedRuntime.pm2SafeName("api"), "api")
        XCTAssertEqual(ManagedRuntime.pm2SafeName("shop-api_v2.0@prod:1"), "shop-api_v2.0@prod:1")
        for bad in ["", "-x", "--all", "all", "ALL", "a b", "a;rm -rf /", "a\nb", "$(id)"] {
            XCTAssertNil(ManagedRuntime.pm2SafeName(bad), bad)
        }
        XCTAssertEqual(ManagedRuntime.pm2SafeName(String(repeating: "a", count: 80))?.count, 64, "capped")
    }

    func testForceMeansKillForDockerAndTheSameVerbForOthers() {
        let container = ManagedRuntime(kind: .docker, name: "web-1", stop: ["docker", "stop", "--", "web-1"])
        XCTAssertEqual(container.stopArguments(force: true), ["docker", "kill", "--", "web-1"])
        XCTAssertEqual(container.stopCommand(force: false), "docker stop -- web-1")
        let pm2 = ManagedRuntime(kind: .pm2, name: "api", stop: ["pm2", "stop", "api"])
        XCTAssertEqual(pm2.stopArguments(force: true), ["pm2", "stop", "api"])
        XCTAssertNil(ManagedRuntime(kind: .reloader, name: "nodemon").stopArguments(force: true))
    }

    func testDescendantsCoverTheWholeSubtreeAndNothingElse() {
        let t = table([(100, 1, "nodemon"), (200, 100, "sh"), (300, 200, "node server.js"), (400, 100, "node worker.js"), (500, 1, "other")])
        XCTAssertEqual(t.descendants(of: 100), [200, 300, 400])
        XCTAssertEqual(t.descendants(of: 300), [])
        XCTAssertEqual(t.descendants(of: 999), [])
    }

    // MARK: - Scanning

    func testConnectionCountsAreMergedNotSummedAcrossAddressFamilies() {
        let scanner = PortScanner()
        var rows: [PortScanner.RawListener] = []
        scanner.mergeListener(PortScanner.RawListener(processName: "node", pid: 1, user: "me", host: "127.0.0.1", port: 3000, connections: 4), into: &rows)
        scanner.mergeListener(PortScanner.RawListener(processName: "node", pid: 1, user: "me", host: "*", port: 3000, connections: 4), into: &rows)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].connections, 4, "each family's row already carries the per-port total")
        XCTAssertEqual(rows[0].host, "*", "the wildcard bind wins so exposure is not masked")
    }

    func testProjectsThatStoppedListeningLeaveTheConfigCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portnanny-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var paths: [String] = []
        for (name, port) in [("shop", 3000), ("api", 4000), ("web", 5000)] {
            let dir = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "PORT=\(port)\n".write(to: dir.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
            paths.append(dir.path)
        }
        let config = ProjectConfig()
        let t0 = Date()
        XCTAssertEqual(config.expectedPorts(in: paths[0], now: t0).map(\.port), [3000])
        XCTAssertEqual(config.expectedPorts(in: paths[1], now: t0).map(\.port), [4000])
        XCTAssertEqual(config.cachedProjectPaths, [paths[0], paths[1]])
        // A new project ten minutes later: the ones nobody asked about since are gone.
        let later = t0.addingTimeInterval(ProjectConfig.forgetAfter + 1)
        XCTAssertEqual(config.expectedPorts(in: paths[2], now: later).map(\.port), [5000])
        XCTAssertEqual(config.cachedProjectPaths, [paths[2]])
    }

    func testRedactionLeavesCleanCommandsUntouched() {
        let clean = "node server.js --port 3000 --host 0.0.0.0"
        XCTAssertEqual(CommandRedaction.redact(clean), clean)
        XCTAssertFalse(CommandRedaction.redact("node app.js --token=abc123").contains("abc123"))
    }

    func testFreePortCanSkipTheBindProbe() {
        XCTAssertEqual(PortNannyCLI.firstFreePort(prefer: 3000, range: 3000...3002, listening: [3000], probe: false), 3001)
        XCTAssertNil(PortNannyCLI.firstFreePort(prefer: 3000, range: 3000...3001, listening: [3000, 3001], probe: false))
    }

    // MARK: - CLI surface

    func testHelpAfterTheDoubleDashBelongsToTheCommand() {
        var expected = CLICommand.ExecOptions()
        expected.port = 3000
        expected.command = ["npm", "run", "dev", "--help"]
        XCTAssertEqual(CLIArguments.parse(["exec", "--port", "3000", "--", "npm", "run", "dev", "--help"]), .success(.exec(expected)))
        XCTAssertEqual(CLIArguments.parse(["exec", "--help"]), .success(.help(topic: "exec")))
        var all = CLICommand.HistoryOptions()
        all.all = true
        XCTAssertEqual(CLIArguments.parse(["history", "--all"]), .success(.history(all)))
    }

    func testTheInstallerRefusesGarbledMarkersAndUnreadableFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("portnanny-docs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let garbled = dir.appendingPathComponent("CLAUDE.md")
        try "\(AgentDocsInstaller.endMarker)\nrules\n\(AgentDocsInstaller.beginMarker)\n".write(to: garbled, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AgentDocsInstaller.install(into: garbled)) { error in
            guard case AgentDocsInstaller.InstallError.markersOutOfOrder = error else { return XCTFail("\(error)") }
        }
        XCTAssertTrue(try String(contentsOf: garbled, encoding: .utf8).contains("rules"), "nothing was rewritten")
        XCTAssertThrowsError(try AgentDocsInstaller.install(into: dir), "a directory is not a rules file")
    }

    func testTheKillToolFlagsEveryOutcomeThatLeavesThePortBusy() {
        XCTAssertEqual(MCPServer.killNotDone, [CLIExit.refused, CLIExit.killFailed, CLIExit.stillRunning, CLIExit.managed])
        XCTAssertFalse(MCPServer.killNotDone.contains(CLIExit.ok))
        XCTAssertFalse(MCPServer.killNotDone.contains(CLIExit.notFound), "a free port is not an error for the agent")
    }

    func testDoctorFindsToolsWhereverTheLocatorLooks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("portnanny-doctor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let codex = dir.appendingPathComponent("codex")
        try "#!/bin/sh\n".write(to: codex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
        let entry = try XCTUnwrap(AgentCatalog.entries.first { $0.executables.contains("codex") })
        XCTAssertEqual(DoctorAgents.installed(entry, path: dir.path), codex.path)
    }
}
