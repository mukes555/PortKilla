import Foundation

/// `portkilla kill`: identity-checked kills of every listener on a port (or
/// one pid), gated by the friendly-fire guard, with machine-readable output.
enum CLIKill {

    struct Report: Encodable {
        let schema = 1
        var action: String
        var port: Int?
        var force: Bool
        var caller: AgentOwner?
        var targets: [Target]
        var reasons: [String]
        var exitCode: Int32

        struct Target: Encodable {
            let pid: Int
            let processName: String
            let port: Int
            let proto: String
            let agentOwner: AgentOwner?
        }
    }

    static func run(_ options: CLICommand.KillOptions) -> Int32 {
        let scan = PortKillaCLI.scan(refreshDocker: false)
        let targets = select(from: scan.ports, options: options)
        var report = Report(
            action: "", port: options.port, force: options.force, caller: scan.caller,
            targets: targets.map { Report.Target(pid: $0.pid, processName: $0.processName, port: $0.port, proto: $0.proto, agentOwner: $0.agentOwner) },
            reasons: [], exitCode: CLIExit.ok
        )

        guard !targets.isEmpty else {
            let what = options.pid.map { "PID \($0) is not listening on any port." } ?? "Nothing is listening on :\(options.port ?? 0)."
            return finish(&report, action: "not-found", exit: CLIExit.notFound, json: options.json, text: what)
        }

        // The guard: refuse the whole request if any target is another agent's.
        let refusals = targets.compactMap { target -> String? in
            if case .refuse(let reason) = KillDecision.forAgent(caller: scan.caller, target: target.agentOwner) {
                return ":\(target.port) (PID \(target.pid)) is \(reason)"
            }
            return nil
        }
        report.reasons = refusals
        if !refusals.isEmpty && !options.force {
            let text = refusals.joined(separator: "\n")
                + "\nRefusing to kill another agent's server. Pass --force to override, or run `portkilla whoami` to check how you are identified."
            let action = options.dryRun ? "would-refuse" : "refused"
            return finish(&report, action: action, exit: CLIExit.refused, json: options.json, text: text, toStderr: !options.dryRun)
        }

        if options.dryRun {
            let text = targets.map { "Would \(options.force ? "force-" : "")kill \($0.processName) (PID \($0.pid)) on :\($0.port)." }.joined(separator: "\n")
            return finish(&report, action: "would-kill", exit: CLIExit.ok, json: options.json, text: text)
        }

        return kill(targets, options: options, report: &report)
    }

    /// Every distinct process on the port, or the one pid asked for.
    static func select(from ports: [PortInfo], options: CLICommand.KillOptions) -> [PortInfo] {
        var seenPids = Set<Int>()
        return ports.filter { port in
            let matches = options.pid.map { $0 == port.pid } ?? (port.port == options.port)
            guard matches, !seenPids.contains(port.pid) else { return false }
            seenPids.insert(port.pid)
            return true
        }
    }

    private static func kill(_ targets: [PortInfo], options: CLICommand.KillOptions, report: inout Report) -> Int32 {
        let killer = ProcessKiller()
        var failures: [String] = []
        var signalled: [PortInfo] = []

        for target in targets {
            do {
                try killer.killProcess(pid: target.pid, force: options.force, expectedName: target.processName)
                signalled.append(target)
            } catch {
                failures.append("\(target.processName) (PID \(target.pid)): \(error.localizedDescription)")
            }
        }

        let stillRunning = waitForExit(signalled.map(\.pid), timeout: PortManager.exitTimeout(force: options.force), killer: killer)
        let killed = signalled.filter { !stillRunning.contains($0.pid) }

        var lines = killed.map { "Killed \($0.processName) (PID \($0.pid)) on :\($0.port)." }
        lines += signalled.filter { stillRunning.contains($0.pid) }.map { "\($0.processName) (PID \($0.pid)) is still running. Try --force." }
        lines += failures.map { "Failed to kill \($0)" }
        report.reasons = failures

        if signalled.isEmpty {
            return finish(&report, action: "failed", exit: CLIExit.killFailed, json: options.json, text: lines.joined(separator: "\n"), toStderr: true)
        }
        if !stillRunning.isEmpty {
            return finish(&report, action: "still-running", exit: CLIExit.stillRunning, json: options.json, text: lines.joined(separator: "\n"))
        }
        return finish(&report, action: "killed", exit: CLIExit.ok, json: options.json, text: lines.joined(separator: "\n"))
    }

    /// Polls because the CLI has no run loop to host dispatch sources.
    private static func waitForExit(_ pids: [Int], timeout: TimeInterval, killer: ProcessKiller) -> Set<Int> {
        var alive = Set(pids)
        let deadline = Date().addingTimeInterval(timeout)
        while !alive.isEmpty && Date() < deadline {
            alive = alive.filter { killer.isProcessRunning($0) }
            if !alive.isEmpty { Thread.sleep(forTimeInterval: 0.1) }
        }
        return alive
    }

    private static func finish(_ report: inout Report, action: String, exit: Int32, json: Bool, text: String, toStderr: Bool = false) -> Int32 {
        report.action = action
        report.exitCode = exit
        if json {
            PortKillaCLI.printJSON(report)
        } else if toStderr {
            PortKillaCLI.printError(text)
        } else {
            print(text)
        }
        return exit
    }
}
