import XCTest
@testable import PortKillaCore

/// End-to-end scenarios against real processes: the debug CLI binary is
/// spawned as a fake agent-started server (its environment carries the
/// markers a real agent would leave) and the guard is exercised through the
/// CLI as a separate process, exit codes and JSON included.
final class ScenarioTests: XCTestCase {

    /// The `portkilla-cli` executable built next to the test bundle.
    private static var cli: URL {
        URL(fileURLWithPath: Bundle(for: ScenarioTests.self).bundlePath)
            .deletingLastPathComponent()
            .appendingPathComponent("portkilla-cli")
    }

    private var servers: [Process] = []
    private var detachedPids: [Int32] = []

    override func tearDown() {
        servers.forEach { $0.terminate() }
        detachedPids.forEach { kill($0, SIGKILL) }
        servers.forEach { waitForExit($0, timeout: 5) }
        servers = []
        detachedPids = []
    }

    /// waitUntilExit has no timeout; a server that survives a failed kill
    /// must not hang the whole suite.
    private func waitForExit(_ process: Process, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            XCTFail("server pid \(process.processIdentifier) survived; killed it")
        }
    }

    /// A server whose parent has exited (reparented to launchd), which is how
    /// agents usually leave them; only its environment says who started it.
    private func startDetachedServer(port: Int, environment: [String: String]) throws -> Int32 {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The server must not inherit the pipe we read the pid from, or the
        // read waits for the server to exit.
        shell.arguments = ["-c", "\"$0\" __serve \"$1\" >/dev/null 2>&1 & echo $!", Self.cli.path, "\(port)"]
        var env = ProcessInfo.processInfo.environment
        for key in AgentSignatures.markerKeys { env[key] = nil }
        environment.forEach { env[$0.key] = $0.value }
        shell.environment = env
        let out = Pipe()
        shell.standardOutput = out
        try shell.run()
        let pid = Int32(String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        shell.waitUntilExit()
        detachedPids.append(pid)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if (NativeScanner.allListeners() ?? []).contains(where: { $0.port == port && $0.pid == Int(pid) }) { return pid }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail("detached server on :\(port) did not start")
        return pid
    }

    /// Spawns `portkilla __serve <port>` with the given environment and waits
    /// until it listens.
    private func startServer(port: Int, environment: [String: String]) throws -> Process {
        let process = Process()
        process.executableURL = Self.cli
        process.arguments = ["__serve", "\(port)"]
        var env = ProcessInfo.processInfo.environment
        // Start from a clean slate: the test runner itself runs under an agent.
        for key in AgentSignatures.markerKeys { env[key] = nil }
        environment.forEach { env[$0.key] = $0.value }
        process.environment = env
        process.standardError = FileHandle.nullDevice
        try process.run()
        servers.append(process)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if (NativeScanner.allListeners() ?? []).contains(where: { $0.port == port && $0.pid == Int(process.processIdentifier) }) {
                return process
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail("server on :\(port) did not start")
        return process
    }

    private struct Run {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Runs the CLI the way a person at a plain terminal reaches it: no
    /// declared owner, no markers, and no agent anywhere above it. The test
    /// runner itself usually sits inside an agent session, so the CLI is
    /// started from a shell that exits at once, which reparents the CLI to
    /// launchd before it looks at its ancestry.
    private func portkillaAsPerson(_ arguments: [String]) throws -> Run {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("portkilla-scenario-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let stdout = dir.appendingPathComponent("stdout")
        let stderr = dir.appendingPathComponent("stderr")
        let status = dir.appendingPathComponent("status")

        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        var env = ProcessInfo.processInfo.environment
        for key in AgentSignatures.markerKeys { env[key] = nil }
        shell.environment = env
        let quoted = arguments.map { "'\($0)'" }.joined(separator: " ")
        // The pause gives the outer shell time to exit before the CLI starts.
        shell.arguments = ["-c", "(sleep 0.2; \"$0\" \(quoted) >\"$1\" 2>\"$2\"; echo $? >\"$3\") >/dev/null 2>&1 &",
                           Self.cli.path, stdout.path, stderr.path, status.path]
        try shell.run()
        shell.waitUntilExit()

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let statusText = (try? String(contentsOf: status, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let statusText, let code = Int32(statusText) {
                return Run(exitCode: code,
                           stdout: (try? String(contentsOf: stdout, encoding: .utf8)) ?? "",
                           stderr: (try? String(contentsOf: stderr, encoding: .utf8)) ?? "")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail("detached CLI run did not finish")
        return Run(exitCode: -1, stdout: "", stderr: "")
    }

    /// Runs the CLI with a caller identity of `owner`, or none.
    private func portkilla(_ arguments: [String], owner: String?) throws -> Run {
        let process = Process()
        process.executableURL = Self.cli
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        for key in AgentSignatures.markerKeys { env[key] = nil }
        if let owner { env["PORTKILLA_OWNER"] = owner }
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return Run(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func json(_ text: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    // MARK: - Scenarios

    func testDetachedServerIsAttributedThroughItsEnvironment() throws {
        // The server's parent is the test runner, not an agent; only the
        // markers say who started it. That is the reparented-to-launchd case.
        let port = 47031
        let server = try startServer(port: port, environment: ["PORTKILLA_OWNER": "scenario-bot"])

        let run = try portkilla(["list", "--json"], owner: nil)
        XCTAssertEqual(run.exitCode, 0, run.stderr)
        let ports = try XCTUnwrap(try json(run.stdout) as? [[String: Any]])
        let row = try XCTUnwrap(ports.first { $0["port"] as? Int == port })
        XCTAssertEqual(row["pid"] as? Int, Int(server.processIdentifier))
        let owner = try XCTUnwrap(row["agentOwner"] as? [String: Any])
        XCTAssertEqual(owner["name"] as? String, "scenario-bot")
        XCTAssertEqual(owner["source"] as? String, "declared")
    }

    func testAnotherAgentIsRefusedAndTheSameOwnerIsAllowed() throws {
        let port = 47032
        let server = try startServer(port: port, environment: ["PORTKILLA_OWNER": "scenario-bot"])

        let refused = try portkilla(["kill", "\(port)", "--dry-run", "--json"], owner: "other-bot")
        XCTAssertEqual(refused.exitCode, CLIExit.refused, refused.stderr)
        let report = try XCTUnwrap(try json(refused.stdout) as? [String: Any])
        XCTAssertEqual(report["action"] as? String, "would-refuse")
        XCTAssertEqual(report["guardVerdict"] as? String, "refused")
        XCTAssertTrue((report["reasons"] as? [String])?.first?.contains("scenario-bot") == true)

        let allowed = try portkilla(["kill", "\(port)", "--dry-run", "--json"], owner: "scenario-bot")
        XCTAssertEqual(allowed.exitCode, 0, allowed.stderr)
        XCTAssertEqual((try json(allowed.stdout) as? [String: Any])?["action"] as? String, "would-kill")

        let forced = try portkilla(["kill", "\(port)", "--dry-run", "--force", "--json"], owner: "other-bot")
        XCTAssertEqual(forced.exitCode, 0)
        let forcedReport = try XCTUnwrap(try json(forced.stdout) as? [String: Any])
        XCTAssertEqual(forcedReport["guardVerdict"] as? String, "overridden")
        XCTAssertFalse((forcedReport["overriddenRefusals"] as? [String])?.isEmpty ?? true)
        XCTAssertTrue(server.isRunning, "dry runs never signal")
    }

    func testAgentMayNotKillAnUnattributedServerButAPersonMay() throws {
        let port = 47033
        // Detached and marker-free: nobody can claim it, whatever runs the tests.
        _ = try startDetachedServer(port: port, environment: [:])

        let agent = try portkilla(["kill", "\(port)", "--dry-run", "--json"], owner: "scenario-bot")
        XCTAssertEqual(agent.exitCode, CLIExit.refused, "an identified agent must not kill what nobody claims")
        XCTAssertTrue((try json(agent.stdout) as? [String: Any])?["reasons"].debugDescription.contains("not attributed") == true)

        let person = try portkillaAsPerson(["kill", "\(port)", "--dry-run", "--json"])
        XCTAssertEqual(person.exitCode, 0, person.stderr)
        XCTAssertEqual((try json(person.stdout) as? [String: Any])?["guardVerdict"] as? String, "not-evaluated: target unknown")
    }

    func testRealKillFreesThePortAndRecordsHistory() throws {
        let port = 47034
        let server = try startServer(port: port, environment: ["PORTKILLA_OWNER": "scenario-bot"])

        let killed = try portkilla(["kill", "\(port)", "--json"], owner: "scenario-bot")
        XCTAssertEqual(killed.exitCode, 0, killed.stderr)
        XCTAssertEqual((try json(killed.stdout) as? [String: Any])?["action"] as? String, "killed")
        waitForExit(server, timeout: 5)
        XCTAssertFalse((NativeScanner.allListeners() ?? []).contains { $0.port == port })

        let free = try portkilla(["free", "\(port)"], owner: "scenario-bot")
        XCTAssertEqual(free.exitCode, 0, "free on a free port is success")
    }

    func testMineListsOnlyWhatIMayStop() throws {
        let mine = 47035, theirs = 47036
        _ = try startServer(port: mine, environment: ["PORTKILLA_OWNER": "scenario-bot"])
        _ = try startServer(port: theirs, environment: ["PORTKILLA_OWNER": "other-bot"])

        let run = try portkilla(["list", "--mine", "--json"], owner: "scenario-bot")
        let ports = try XCTUnwrap(try json(run.stdout) as? [[String: Any]]).compactMap { $0["port"] as? Int }
        XCTAssertTrue(ports.contains(mine))
        XCTAssertFalse(ports.contains(theirs))
    }

    func testDetachedServerCarriesItsMarkersAfterReparenting() throws {
        // Parent gone; ppid is launchd. CLAUDECODE=1 alone names the tool but
        // no session (no CLAUDE_PID), so it is "Claude Code" and, as long as
        // any Claude Code process runs on this machine, a live one.
        let port = 47038
        let pid = try startDetachedServer(port: port, environment: ["CLAUDECODE": "1"])
        XCTAssertEqual(ProcessTable.capture().ppid(for: Int(pid)), 1, "reparented to launchd")

        let run = try portkilla(["list", "--json"], owner: nil)
        let ports = try XCTUnwrap(try json(run.stdout) as? [[String: Any]])
        let row = try XCTUnwrap(ports.first { $0["port"] as? Int == port })
        let owner = try XCTUnwrap(row["agentOwner"] as? [String: Any])
        XCTAssertEqual(owner["name"] as? String, "Claude Code")
        XCTAssertEqual(owner["source"] as? String, "environment")
    }

    func testWhoamiThroughAProcess() throws {
        let run = try portkilla(["whoami", "--json"], owner: "scenario-bot")
        let report = try XCTUnwrap(try json(run.stdout) as? [String: Any])
        XCTAssertEqual(report["detected"] as? Bool, true)
        XCTAssertEqual((report["owner"] as? [String: Any])?["name"] as? String, "scenario-bot")
    }

    func testFreePortSkipsTheOccupiedOne() throws {
        let taken = 47037
        _ = try startServer(port: taken, environment: [:])
        let run = try portkilla(["free-port", "--prefer", "\(taken)", "--range", "\(taken)-\(taken + 5)"], owner: nil)
        XCTAssertEqual(run.exitCode, 0, run.stderr)
        let chosen = Int(run.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertNotNil(chosen)
        XCTAssertNotEqual(chosen, taken)
        XCTAssertTrue((taken...(taken + 5)).contains(chosen ?? -1))
    }
}
