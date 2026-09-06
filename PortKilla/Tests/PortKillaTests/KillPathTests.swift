import XCTest
@testable import PortKilla

/// Tests for the code that can end a process without a person in the loop.
final class KillPathTests: XCTestCase {

    private func spawnSleep(_ seconds: Int = 30) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["\(seconds)"]
        try p.run()
        return p
    }

    // MARK: - waitForExit

    func testWaitForExitReportsKilledAndSurvivingPids() throws {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        let dies = try spawnSleep()
        let survives = try spawnSleep()
        defer { survives.terminate() }

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { dies.terminate() }
        let dead = manager.waitForExit(pids: [Int(dies.processIdentifier), Int(survives.processIdentifier)], timeout: 2.0)

        XCTAssertEqual(dead, [Int(dies.processIdentifier)])
    }

    func testWaitForExitCountsAlreadyDeadPidsAndRespectsTheTimeout() throws {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        let gone = try spawnSleep()
        gone.terminate()
        gone.waitUntilExit()
        let alive = try spawnSleep()
        defer { alive.terminate() }

        let start = Date()
        let dead = manager.waitForExit(pids: [Int(gone.processIdentifier), Int(alive.processIdentifier)], timeout: 0.3)
        XCTAssertEqual(dead, [Int(gone.processIdentifier)])
        XCTAssertLessThan(Date().timeIntervalSince(start), ScanBenchmarkTests.budget(1.5), "must give up at the deadline")
    }

    // MARK: - guardKillTarget

    private func port(_ number: Int, name: String, command: String = "/Users/me/app", user: String = NSUserName()) -> PortInfo {
        PortInfo(port: number, pid: number, processName: name, command: command, user: user,
                 memoryUsage: "", memorySizeKB: 0, type: .nodejs)
    }

    func testGuardOnlyFiresOnUnprotectedUserOwnedOccupantsOfGuardedPorts() {
        let manager = PortManager.forTesting()
        defer { manager.discardTestDefaults() }
        manager.watchedPorts = [3000, 3001, 3002, 3003]
        manager.guardedPorts = [3000, 3001, 3002]
        manager.protectedProcessSubstrings = ["cursor"]

        let ports = [
            port(3000, name: "node"),
            port(3001, name: "Cursor Helper"),
            port(3002, name: "mDNSResponder", command: "/usr/sbin/mDNSResponder", user: "root"),
            port(3003, name: "node"),
        ]
        XCTAssertEqual(manager.guardKillTarget(for: 3000, in: ports)?.pid, 3000)
        XCTAssertNil(manager.guardKillTarget(for: 3001, in: ports), "protected names are never guard-killed")
        XCTAssertNil(manager.guardKillTarget(for: 3002, in: ports), "system ports are never guard-killed")
        XCTAssertNil(manager.guardKillTarget(for: 3003, in: ports), "watched but not guarded")
        XCTAssertNil(manager.guardKillTarget(for: 4000, in: ports), "nothing there")
    }

    // MARK: - URL scheme

    func testURLCommandParsing() {
        XCTAssertEqual(URLCommand.parse(URL(string: "portkilla://kill/3000")!), .kill(port: 3000, force: false))
        XCTAssertEqual(URLCommand.parse(URL(string: "portkilla://kill/3000?force=1")!), .kill(port: 3000, force: true))
        XCTAssertEqual(URLCommand.parse(URL(string: "portkilla://kill/3000?force=0")!), .kill(port: 3000, force: false))
        XCTAssertEqual(URLCommand.parse(URL(string: "portkilla://show")!), .show)
        XCTAssertNil(URLCommand.parse(URL(string: "portkilla://kill/abc")!))
        XCTAssertNil(URLCommand.parse(URL(string: "portkilla://kill/70000")!))
        XCTAssertNil(URLCommand.parse(URL(string: "portkilla://reboot")!))
    }
}
