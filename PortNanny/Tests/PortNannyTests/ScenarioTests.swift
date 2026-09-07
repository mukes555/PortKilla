import XCTest
@testable import PortNannyCore

/// End-to-end scenarios against real processes: the debug CLI binary is
/// spawned as a fake agent-started server (its environment carries the
/// markers a real agent would leave) and the guard is exercised through the
/// CLI as a separate process, exit codes and JSON included.
final class ScenarioTests: XCTestCase {

    /// The `portnanny-cli` executable built next to the test bundle.
    private static var cli: URL {
        URL(fileURLWithPath: Bundle(for: ScenarioTests.self).bundlePath)
            .deletingLastPathComponent()
            .appendingPathComponent("portnanny-cli")
    }

    private var servers: [Process] = []
    private var detachedPids: [Int32] = []

    /// The CLI writes History to this throwaway domain instead of the user's.
    private static let suite = "com.mukes555.PortNanny.scenario"

    override func tearDown() {
        servers.forEach { $0.terminate() }
        detachedPids.forEach { kill($0, SIGKILL) }
        servers.forEach { waitForExit($0, timeout: 5) }
        servers = []
        detachedPids = []
        UserDefaults.standard.removePersistentDomain(forName: Self.suite)
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

    /// A server under a fake reloader: a shell whose command line says
    /// "nodemon" runs the server in the foreground, the way nodemon does.
    /// Returns the shell; the listener's pid is tracked for teardown.
    private func startSupervisedServer(port: Int) throws -> Process {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Two commands, so sh forks instead of exec'ing the server in place.
        shell.arguments = ["-c", "\"$0\" __serve \"$1\"; exit $?", Self.cli.path, "\(port)", "nodemon-lookalike"]
        var env = ProcessInfo.processInfo.environment
        for key in AgentSignatures.markerKeys { env[key] = nil }
        env["PORTNANNY_OWNER"] = "scenario-bot"
        shell.environment = env
        shell.standardError = FileHandle.nullDevice
        try shell.run()
        servers.append(shell)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let listener = (NativeScanner.allListeners() ?? []).first(where: { $0.port == port }) {
                detachedPids.append(Int32(listener.pid))
                return shell
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail("supervised server on :\(port) did not start")
        return shell
    }

    /// Spawns `portnanny __serve <port>` with the given environment (and
    /// working directory) and waits until it listens.
    private func startServer(port: Int, environment: [String: String], cwd: URL? = nil) throws -> Process {
        let process = Process()
        process.executableURL = Self.cli
        process.arguments = ["__serve", "\(port)"]
        process.currentDirectoryURL = cwd
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
    private func portnannyAsPerson(_ arguments: [String]) throws -> Run {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("portnanny-scenario-\(UUID().uuidString)")
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

    /// Polls until the process is gone; detached servers are not children,
    /// so there is no Process to wait on.
    private func waitUntilGone(_ pid: Int32, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while kill(pid, 0) == 0 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertNotEqual(kill(pid, 0), 0, "pid \(pid) is still running")
    }

    /// Runs the CLI with a caller identity of `owner` (and `session`), or none.
    private func portnanny(_ arguments: [String], owner: String?, session: String? = nil) throws -> Run {
        let process = Process()
        process.executableURL = Self.cli
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        for key in AgentSignatures.markerKeys { env[key] = nil }
        env["PORTNANNY_DEFAULTS_SUITE"] = Self.suite
        if let owner { env["PORTNANNY_OWNER"] = owner }
        if let session { env["PORTNANNY_SESSION"] = session }
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
        let server = try startServer(port: port, environment: ["PORTNANNY_OWNER": "scenario-bot"])

        let run = try portnanny(["list", "--json"], owner: nil)
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
        let server = try startServer(port: port, environment: ["PORTNANNY_OWNER": "scenario-bot"])

        let refused = try portnanny(["kill", "\(port)", "--dry-run", "--json"], owner: "other-bot")
        XCTAssertEqual(refused.exitCode, CLIExit.refused, refused.stderr)
        let report = try XCTUnwrap(try json(refused.stdout) as? [String: Any])
        XCTAssertEqual(report["action"] as? String, "would-refuse")
        XCTAssertEqual(report["guardVerdict"] as? String, "refused")
        XCTAssertTrue((report["reasons"] as? [String])?.first?.contains("scenario-bot") == true)

        let allowed = try portnanny(["kill", "\(port)", "--dry-run", "--json"], owner: "scenario-bot")
        XCTAssertEqual(allowed.exitCode, 0, allowed.stderr)
        XCTAssertEqual((try json(allowed.stdout) as? [String: Any])?["action"] as? String, "would-kill")

        let forced = try portnanny(["kill", "\(port)", "--dry-run", "--force", "--json"], owner: "other-bot")
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

        let agent = try portnanny(["kill", "\(port)", "--dry-run", "--json"], owner: "scenario-bot")
        XCTAssertEqual(agent.exitCode, CLIExit.refused, "an identified agent must not kill what nobody claims")
        XCTAssertTrue((try json(agent.stdout) as? [String: Any])?["reasons"].debugDescription.contains("not attributed") == true)

        let person = try portnannyAsPerson(["kill", "\(port)", "--dry-run", "--json"])
        XCTAssertEqual(person.exitCode, 0, person.stderr)
        XCTAssertEqual((try json(person.stdout) as? [String: Any])?["guardVerdict"] as? String, "not-evaluated: target unknown")
    }

    func testWhoisExplainsADeclaredOwnerAndItsSession() throws {
        let port = 47039
        _ = try startServer(port: port, environment: ["PORTNANNY_OWNER": "scenario-bot", "PORTNANNY_SESSION": "session-one"])

        let same = try portnanny(["whois", "\(port)", "--json"], owner: "scenario-bot")
        XCTAssertEqual(same.exitCode, 0, same.stderr)
        let report = try XCTUnwrap(try json(same.stdout) as? [String: Any])
        let target = try XCTUnwrap((report["targets"] as? [[String: Any]])?.first)
        let owner = try XCTUnwrap(target["agentOwner"] as? [String: Any])
        XCTAssertEqual(owner["name"] as? String, "scenario-bot")
        XCTAssertEqual(owner["sessionKey"] as? String, "session-one")
        let evidence = try XCTUnwrap(target["evidence"] as? [String: Any])
        XCTAssertEqual(evidence["decidedBy"] as? String, "declared")
        XCTAssertEqual(evidence["declaredOwner"] as? String, "scenario-bot")
        // Under an agent (a developer's Claude Code running the suite) both the
        // caller and the server borrow that session, so they are the same one;
        // on CI nothing attaches, and a name alone cannot claim a known session.
        let callerHasSession = (report["caller"] as? [String: Any])?["sessionPid"] != nil
        XCTAssertEqual(target["verdict"] as? String, callerHasSession ? "allowed" : "refused", same.stdout)

        let other = try portnanny(["whois", "\(port)"], owner: "scenario-bot", session: "session-two")
        XCTAssertEqual(other.exitCode, 0, other.stderr)
        XCTAssertTrue(other.stdout.contains("kill       refused: owned by another scenario-bot session (scenario-bot@session-one)"), other.stdout)
        XCTAssertTrue(other.stdout.contains("owner      scenario-bot"), other.stdout)
        XCTAssertTrue(other.stdout.contains("declared via PORTNANNY_OWNER"), other.stdout)
    }

    func testOrphanedServersAreListedAndCleanedUp() throws {
        let port = 47040
        // Started by a Claude Code session whose pid no longer exists.
        let pid = try startDetachedServer(port: port, environment: ["CLAUDECODE": "1", "CLAUDE_PID": "999999"])

        let listed = try portnanny(["list", "--orphaned", "--json"], owner: nil)
        let ports = try XCTUnwrap(try json(listed.stdout) as? [[String: Any]])
        XCTAssertTrue(ports.contains { $0["port"] as? Int == port }, listed.stdout)

        let planned = try portnanny(["kill", "--orphaned", "--dry-run", "--json"], owner: "scenario-bot")
        XCTAssertEqual(planned.exitCode, 0, planned.stderr)
        let plan = try XCTUnwrap(try json(planned.stdout) as? [String: Any])
        XCTAssertEqual(plan["action"] as? String, "would-kill")
        let targets = try XCTUnwrap(plan["targets"] as? [[String: Any]])
        XCTAssertTrue(targets.contains { $0["pid"] as? Int == Int(pid) }, planned.stdout)

        // The real sweep takes every orphan on the machine; only run it when
        // ours is the only one, so a developer's leftovers are not swept.
        guard targets.count == 1 else {
            throw XCTSkip("other orphaned servers exist on this machine; sweep not exercised")
        }
        let cleaned = try portnanny(["kill", "--orphaned", "--json"], owner: "scenario-bot")
        XCTAssertEqual(cleaned.exitCode, 0, cleaned.stderr)
        XCTAssertEqual((try json(cleaned.stdout) as? [String: Any])?["action"] as? String, "killed")
        waitUntilGone(pid, timeout: 5)
    }

    func testAReloaderIsStoppedInsteadOfItsChild() throws {
        let port = 47041
        let supervisor = try startSupervisedServer(port: port)
        let supervisorPid = Int(supervisor.processIdentifier)

        let planned = try portnanny(["kill", "\(port)", "--dry-run", "--json"], owner: "scenario-bot")
        XCTAssertEqual(planned.exitCode, 0, planned.stderr)
        let plan = try XCTUnwrap(try json(planned.stdout) as? [String: Any])
        let target = try XCTUnwrap((plan["targets"] as? [[String: Any]])?.first)
        let managed = try XCTUnwrap(target["managedBy"] as? [String: Any], "the shell's command line names nodemon")
        XCTAssertEqual(managed["kind"] as? String, "reloader")
        XCTAssertEqual(managed["name"] as? String, "nodemon")
        XCTAssertEqual(managed["supervisorPid"] as? Int, supervisorPid)
        let text = try portnanny(["kill", "\(port)", "--dry-run"], owner: "scenario-bot")
        XCTAssertTrue(text.stdout.hasPrefix("Would stop nodemon (PID \(supervisorPid)) instead of"), text.stdout)

        let killed = try portnanny(["kill", "\(port)", "--json"], owner: "scenario-bot")
        XCTAssertEqual(killed.exitCode, 0, killed.stderr)
        let report = try XCTUnwrap(try json(killed.stdout) as? [String: Any])
        XCTAssertEqual(report["action"] as? String, "killed")
        // The kernel names /bin/sh "bash" on macOS; the pid is what matters.
        XCTAssertTrue((report["stoppedVia"] as? [String])?.first?.hasSuffix("(PID \(supervisorPid))") == true, killed.stdout)
        waitForExit(supervisor, timeout: 5)
        XCTAssertTrue(ManagedRuntime.waitForPortsFree([port], timeout: 5).isEmpty, "the child went down with its supervisor")
    }

    func testARefusalIsRecordedAndSignalledToTheApp() throws {
        let port = 47042
        _ = try startServer(port: port, environment: ["PORTNANNY_OWNER": "scenario-bot"])
        let signalled = expectation(forNotification: RefusalSignal.name, object: nil, notificationCenter: DistributedNotificationCenter.default()) { note in
            RefusalSignal.Payload(userInfo: note.userInfo)?.port == port
        }

        let refused = try portnanny(["kill", "\(port)"], owner: "other-bot")
        XCTAssertEqual(refused.exitCode, CLIExit.refused, refused.stdout)
        wait(for: [signalled], timeout: 5)

        // Kills only by default, so `.[0].killedBy` never names an agent that
        // was refused; --all adds the refusals.
        let kills = try portnanny(["history", "--json", "--port", "\(port)"], owner: nil)
        XCTAssertFalse(kills.stdout.contains("Refused"), kills.stdout)
        let history = try portnanny(["history", "--json", "--port", "\(port)", "--all"], owner: nil)
        let items = try XCTUnwrap(try json(history.stdout) as? [[String: Any]])
        let refusal = try XCTUnwrap(items.first { $0["action"] as? String == "Refused" }, history.stdout)
        // Under a developer's agent the caller borrows that session ("other-bot
        // (session N)"); on CI it has none.
        let refusedCaller = try XCTUnwrap(refusal["killedBy"] as? String)
        XCTAssertTrue(refusedCaller.hasPrefix("other-bot") && refusedCaller.hasSuffix(" via CLI"), refusedCaller)
        XCTAssertEqual(refusal["owner"] as? String, "scenario-bot")
        let text = try portnanny(["history", "--port", "\(port)", "--all"], owner: nil)
        XCTAssertTrue(text.stdout.contains("refused: other-bot"), text.stdout)
    }

    func testLeasesKeepFreePortAndKillHonest() throws {
        let port = 47043
        let taken = try portnanny(["reserve", "\(port)", "--for", "5m", "--reason", "scenario", "--json"], owner: "scenario-bot", session: "s1")
        XCTAssertEqual(taken.exitCode, 0, taken.stderr)
        XCTAssertEqual((try json(taken.stdout) as? [String: Any])?["action"] as? String, "reserved")

        // Another agent cannot take it, and free-port walks past it.
        let refused = try portnanny(["reserve", "\(port)", "--json"], owner: "other-bot")
        XCTAssertEqual(refused.exitCode, CLIExit.refused)
        let skipped = try portnanny(["free-port", "--prefer", "\(port)", "--range", "\(port)-\(port + 3)"], owner: "other-bot")
        XCTAssertEqual(skipped.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "\(port + 1)", skipped.stderr)
        // The holder's own session gets it back from free-port and can renew.
        let mine = try portnanny(["free-port", "--prefer", "\(port)", "--range", "\(port)-\(port + 3)"], owner: "scenario-bot", session: "s1")
        XCTAssertEqual(mine.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "\(port)")
        XCTAssertEqual((try json(try portnanny(["reserve", "\(port)", "--json"], owner: "scenario-bot", session: "s1").stdout) as? [String: Any])?["action"] as? String, "renewed")

        // A server on the leased port: another agent's kill is refused because of the lease.
        _ = try startServer(port: port, environment: [:])
        let kill = try portnanny(["kill", "\(port)", "--dry-run", "--json"], owner: "other-bot")
        XCTAssertEqual(kill.exitCode, CLIExit.refused)
        XCTAssertTrue((try json(kill.stdout) as? [String: Any])?["reasons"].debugDescription.contains("reserved by scenario-bot") == true, kill.stdout)

        XCTAssertEqual(try portnanny(["release", "\(port)"], owner: "other-bot").exitCode, CLIExit.refused)
        XCTAssertEqual(try portnanny(["release", "\(port)"], owner: "scenario-bot", session: "s1").exitCode, 0)
        XCTAssertEqual(try portnanny(["release", "\(port)"], owner: "scenario-bot").exitCode, CLIExit.notFound)
    }

    func testExecLeasesThePortAndAttributesTheServer() throws {
        let port = 47044
        let runner = Process()
        runner.executableURL = Self.cli
        runner.arguments = ["exec", "--port", "\(port)", "--owner", "exec-bot", "--session", "run-1", "--", Self.cli.path, "__serve", "\(port)"]
        var env = ProcessInfo.processInfo.environment
        for key in AgentSignatures.markerKeys { env[key] = nil }
        env["PORTNANNY_DEFAULTS_SUITE"] = Self.suite
        runner.environment = env
        runner.standardError = FileHandle.nullDevice
        try runner.run()
        servers.append(runner)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !(NativeScanner.allListeners() ?? []).contains(where: { $0.port == port }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if let listener = (NativeScanner.allListeners() ?? []).first(where: { $0.port == port }) {
            detachedPids.append(Int32(listener.pid))
        }

        let leases = try XCTUnwrap(try json(try portnanny(["reservations", "--json"], owner: nil).stdout) as? [[String: Any]])
        let lease = try XCTUnwrap(leases.first { $0["port"] as? Int == port }, "exec leases the port for the run")
        XCTAssertEqual(lease["owner"] as? String, "exec-bot")
        XCTAssertEqual(lease["sessionKey"] as? String, "run-1")

        let who = try portnanny(["whois", "\(port)", "--json"], owner: nil)
        let target = try XCTUnwrap((try json(who.stdout) as? [String: Any])?["targets"] as? [[String: Any]]).first
        XCTAssertEqual((target?["agentOwner"] as? [String: Any])?["name"] as? String, "exec-bot", "the child carries the identity exec exported")
        XCTAssertEqual((target?["agentOwner"] as? [String: Any])?["sessionKey"] as? String, "run-1")

        // Stopping exec stops the child and gives the lease back.
        runner.terminate()
        waitForExit(runner, timeout: 5)
        XCTAssertTrue(ManagedRuntime.waitForPortsFree([port], timeout: 5).isEmpty, "the child died with exec")
        let after = try XCTUnwrap(try json(try portnanny(["reservations", "--json"], owner: nil).stdout) as? [[String: Any]])
        XCTAssertFalse(after.contains { $0["port"] as? Int == port }, "the lease is released")
    }

    func testAServerOffItsConfiguredPortShowsTheDrift() throws {
        let wanted = 47045
        let project = FileManager.default.temporaryDirectory.appendingPathComponent("portnanny-drift-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }
        try "PORT=\(wanted)\n".write(to: project.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        // __serve is "Other" to the classifier; a package.json makes the folder a Node project.
        try #"{"name": "drift-scenario", "scripts": {"dev": "node server.js"}}"#.write(to: project.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        _ = try startServer(port: wanted + 1, environment: ["PORTNANNY_OWNER": "scenario-bot"], cwd: project)
        let listed = try portnanny(["list", "--json"], owner: nil)
        let row = try XCTUnwrap((try json(listed.stdout) as? [[String: Any]])?.first { $0["port"] as? Int == wanted + 1 })
        let expected = try XCTUnwrap(row["expectedPort"] as? [String: Any], "the project's .env names the port it meant: \(row)")
        XCTAssertEqual(expected["port"] as? Int, wanted)
        XCTAssertEqual(expected["source"] as? String, ".env PORT")

        let drift = try portnanny(["drift", "--json"], owner: nil)
        let drifted = try XCTUnwrap((try json(drift.stdout) as? [String: Any])?["drifted"] as? [[String: Any]])
        XCTAssertTrue(drifted.contains { $0["port"] as? Int == wanted + 1 }, drift.stdout)
        let text = try portnanny(["drift"], owner: nil)
        XCTAssertTrue(text.stdout.contains("runs on :\(wanted + 1); .env PORT says :\(wanted), which is free now"), text.stdout)
    }

    func testRealKillFreesThePortAndRecordsHistory() throws {
        let port = 47034
        let server = try startServer(port: port, environment: ["PORTNANNY_OWNER": "scenario-bot"])

        let killed = try portnanny(["kill", "\(port)", "--json"], owner: "scenario-bot")
        XCTAssertEqual(killed.exitCode, 0, killed.stderr)
        XCTAssertEqual((try json(killed.stdout) as? [String: Any])?["action"] as? String, "killed")
        waitForExit(server, timeout: 5)
        XCTAssertFalse((NativeScanner.allListeners() ?? []).contains { $0.port == port })

        let free = try portnanny(["free", "\(port)"], owner: "scenario-bot")
        XCTAssertEqual(free.exitCode, 0, "free on a free port is success")
    }

    func testMineListsOnlyWhatIMayStop() throws {
        let mine = 47035, theirs = 47036
        _ = try startServer(port: mine, environment: ["PORTNANNY_OWNER": "scenario-bot"])
        _ = try startServer(port: theirs, environment: ["PORTNANNY_OWNER": "other-bot"])

        let run = try portnanny(["list", "--mine", "--json"], owner: "scenario-bot")
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

        let run = try portnanny(["list", "--json"], owner: nil)
        let ports = try XCTUnwrap(try json(run.stdout) as? [[String: Any]])
        let row = try XCTUnwrap(ports.first { $0["port"] as? Int == port })
        let owner = try XCTUnwrap(row["agentOwner"] as? [String: Any])
        XCTAssertEqual(owner["name"] as? String, "Claude Code")
        XCTAssertEqual(owner["source"] as? String, "environment")
    }

    func testWhoamiThroughAProcess() throws {
        let run = try portnanny(["whoami", "--json"], owner: "scenario-bot")
        let report = try XCTUnwrap(try json(run.stdout) as? [String: Any])
        XCTAssertEqual(report["detected"] as? Bool, true)
        XCTAssertEqual((report["owner"] as? [String: Any])?["name"] as? String, "scenario-bot")
    }

    func testFreePortSkipsTheOccupiedOne() throws {
        let taken = 47037
        _ = try startServer(port: taken, environment: [:])
        let run = try portnanny(["free-port", "--prefer", "\(taken)", "--range", "\(taken)-\(taken + 5)"], owner: nil)
        XCTAssertEqual(run.exitCode, 0, run.stderr)
        let chosen = Int(run.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertNotNil(chosen)
        XCTAssertNotEqual(chosen, taken)
        XCTAssertTrue((taken...(taken + 5)).contains(chosen ?? -1))
    }
}
