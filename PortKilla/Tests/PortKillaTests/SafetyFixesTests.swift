import XCTest
@testable import PortKilla

/// Regression tests for the v1.9.0 safety batch.
final class SafetyFixesTests: XCTestCase {

    // MARK: - Preferences are untrusted input

    func testRefreshIntervalIsClamped() {
        XCTAssertEqual(PortManager.sanitizedRefreshInterval(0.01), 1.0)
        XCTAssertEqual(PortManager.sanitizedRefreshInterval(9999), 300)
        XCTAssertEqual(PortManager.sanitizedRefreshInterval(0), 0)      // manual mode
        XCTAssertEqual(PortManager.sanitizedRefreshInterval(-5), 0)
        XCTAssertEqual(PortManager.sanitizedRefreshInterval(.nan), 2.0)
        XCTAssertEqual(PortManager.sanitizedRefreshInterval(.infinity), 2.0)
        XCTAssertEqual(PortManager.sanitizedRefreshInterval(2.0), 2.0)
    }

    func testPortNumberValidation() {
        XCTAssertTrue(PortManager.isValidPortNumber(1))
        XCTAssertTrue(PortManager.isValidPortNumber(65535))
        XCTAssertFalse(PortManager.isValidPortNumber(0))
        XCTAssertFalse(PortManager.isValidPortNumber(-3000))
        XCTAssertFalse(PortManager.isValidPortNumber(70000))
    }

    // MARK: - Guard stands down on a process that keeps coming back

    func testGuardStandsDownAfterRepeatedStrikes() {
        let manager = PortManager()
        defer { manager.stopAutoRefresh() }
        XCTAssertFalse(manager.guardHasStruckOut(on: 3000))
        XCTAssertFalse(manager.guardHasStruckOut(on: 3000))
        XCTAssertFalse(manager.guardHasStruckOut(on: 3000))
        XCTAssertTrue(manager.guardHasStruckOut(on: 3000), "fourth strike within the window stands the guard down")
        XCTAssertFalse(manager.guardHasStruckOut(on: 3001), "ports are counted independently")
    }

    // MARK: - Update check distinguishes failure from "up to date"

    func testUpdateCheckReportsFailures() {
        let ok = HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 200, httpVersion: nil, headerFields: nil)
        let limited = HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 403, httpVersion: nil, headerFields: nil)
        let body = #"{"tag_name": "v9.9.9"}"#.data(using: .utf8)!

        XCTAssertEqual(UpdateChecker.evaluate(data: body, response: ok, error: nil, current: "1.0.0"), .newer("9.9.9"))
        XCTAssertEqual(UpdateChecker.evaluate(data: body, response: ok, error: nil, current: "9.9.9"), .upToDate)
        if case .failed = UpdateChecker.evaluate(data: body, response: limited, error: nil, current: "1.0.0") {} else {
            XCTFail("a 403 must not read as up to date")
        }
        let offline = URLError(.notConnectedToInternet)
        if case .failed = UpdateChecker.evaluate(data: nil, response: nil, error: offline, current: "1.0.0") {} else {
            XCTFail("a transport error must not read as up to date")
        }
        if case .failed = UpdateChecker.evaluate(data: Data("nope".utf8), response: ok, error: nil, current: "1.0.0") {} else {
            XCTFail("garbage must not read as up to date")
        }
    }

    // MARK: - CSV formula lead-ins

    func testCSVDefusesTabAndCarriageReturnLeadIns() {
        XCTAssertEqual(CSV.field("\tcmd"), "'\tcmd")
        XCTAssertEqual(CSV.field("\rcmd"), "\"'\rcmd\"")
        XCTAssertEqual(CSV.field("node"), "node")
    }

    // MARK: - Kill waits depend on the signal

    func testExitTimeoutGivesSIGTERMTimeToUnwind() {
        XCTAssertGreaterThan(PortManager.exitTimeout(force: false), PortManager.exitTimeout(force: true))
    }

    // MARK: - Subprocess timeouts must not leak

    func testTimedOutCommandsDoNotExhaustTheRunner() throws {
        // Each timeout used to park a thread in read(2) and leak the pipe fd;
        // after ~64 of them the global queues stopped scheduling. Burn through
        // more than that and prove the runner still works afterwards.
        let openFdsBefore = openFileDescriptorCount()
        for _ in 0..<70 {
            XCTAssertThrowsError(try CommandRunner.run("/bin/sleep", ["5"], timeout: 0.05))
        }
        let echoed = try CommandRunner.run("/bin/echo", ["still alive"])
        XCTAssertEqual(echoed.trimmingCharacters(in: .whitespacesAndNewlines), "still alive")
        XCTAssertLessThan(openFileDescriptorCount(), openFdsBefore + 10, "pipe descriptors leaked across timeouts")
    }

    func testCommandOutputIsCapturedInFull() throws {
        // Larger than a pipe buffer, so the reader must drain concurrently.
        let output = try CommandRunner.run("/usr/bin/head", ["-c", "200000", "/dev/zero"])
        XCTAssertEqual(output.utf8.count, 200000)
    }

    private func openFileDescriptorCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0
    }

    // MARK: - Environment markers are read from our own process

    func testEnvironmentMarkersReadOnlyAllowlistedKeys() {
        // macOS withholds the environment of platform (OS-signed) binaries such
        // as /bin/sleep from unprivileged readers, and the kernel copy reflects
        // exec time, not setenv. So read the test runner itself, using a
        // variable it was launched with.
        let home = ProcessInfo.processInfo.environment["HOME"]
        XCTAssertNotNil(home)

        let markers = NativeScanner.environmentMarkers(getpid(), keys: ["HOME"])
        XCTAssertEqual(markers, ["HOME": home ?? ""])
    }

    func testCommandLineStillParsesAfterRefactor() {
        let command = NativeScanner.commandLine(getpid())
        XCTAssertNotNil(command)
        XCTAssertTrue(command?.contains("xctest") == true || command?.contains("PortKilla") == true)
    }

    // MARK: - Tree kill uses one snapshot

    func testParentMapKnowsOurOwnParent() {
        let parents = NativeScanner.parentMap()
        XCTAssertEqual(parents[getpid()], getppid())
    }
}
