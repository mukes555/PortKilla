import Foundation

/// `portkilla kill`: identity-checked kills of every listener on a port (or
/// one pid), gated by the friendly-fire guard, with machine-readable output.
public enum CLIKill {

    public struct Report: Encodable {
        let schema = 1
        var action: String
        var port: Int?
        var force: Bool
        var caller: AgentOwner?
        var targets: [Target]
        var reasons: [String]
        /// Refusals that --force overrode: the audit trail of whose server
        /// was killed against the guard's advice.
        var overriddenRefusals: [String] = []
        /// "refused", "allowed", "overridden", or "not-evaluated: …" so an
        /// agent can tell "checked and cleared" from "could not check".
        var guardVerdict = ""
        var exitCode: Int32

        struct Target: Encodable {
            let pid: Int
            let processName: String
            let port: Int
            let proto: String
            let agentOwner: AgentOwner?
            let connections: Int
        }
    }

    /// What a kill produced: the report for JSON consumers, the text for
    /// people, and where the text belongs.
    public struct Outcome {
        let report: Report
        let text: String
        let toStderr: Bool
    }

    public static func run(_ options: CLICommand.KillOptions) -> Int32 {
        let outcome = perform(options)
        if options.json {
            return PortKillaCLI.printJSON(outcome.report) ? outcome.report.exitCode : CLIExit.internalError
        }
        if outcome.toStderr {
            PortKillaCLI.printError(outcome.text)
        } else {
            print(outcome.text)
        }
        return outcome.report.exitCode
    }

    /// The whole kill decision and action, without touching stdout: the CLI
    /// prints the outcome, the MCP server wraps it in a tool result.
    public static func perform(_ options: CLICommand.KillOptions) -> Outcome {
        let scan = PortKillaCLI.scan(refreshDocker: false)
        let targets = select(from: scan.ports, options: options)
        var report = Report(
            action: "", port: options.port, force: options.force, caller: scan.caller,
            targets: targets.map { Report.Target(pid: $0.pid, processName: $0.processName, port: $0.port, proto: $0.proto, agentOwner: $0.agentOwner, connections: $0.connections) },
            reasons: [], exitCode: CLIExit.ok
        )

        guard !targets.isEmpty else {
            let what = options.pid.map { "PID \($0) is not listening on any port." } ?? "Nothing is listening on :\(options.port ?? 0)."
            // `free` treats an already-free port as done.
            let exit = options.freeIsSuccess && options.pid == nil ? CLIExit.ok : CLIExit.notFound
            return finish(&report, action: exit == CLIExit.ok ? "already-free" : "not-found", exit: exit, text: what)
        }
        report.guardVerdict = targets.map { KillDecision.verdict(caller: scan.caller, target: $0.agentOwner, forced: options.force) }
            .first { $0 != "allowed" } ?? "allowed"
        var notes: [String] = []
        if scan.caller == nil, let owned = targets.first(where: { $0.agentOwner?.isLiveAgentSession == true }) {
            // The guard can't protect what it can't compare against.
            notes.append("note: :\(owned.port) belongs to \(owned.agentOwner?.described ?? "an agent") and you are not identified as an agent, so the friendly-fire guard did not apply. Run `portkilla whoami` or export PORTKILLA_OWNER=<name>.")
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
                + "\nRefusing to kill another agent's server. Ask the user, or start yours on a free port. Pass --force only if the user says so; run `portkilla whoami` to check how you are identified."
            let action = options.dryRun ? "would-refuse" : "refused"
            return finish(&report, action: action, exit: CLIExit.refused, text: text, toStderr: !options.dryRun)
        }

        if options.force && !refusals.isEmpty {
            report.overriddenRefusals = refusals
            report.reasons = []
        }

        if options.dryRun {
            let text = targets.map { target -> String in
                let clients = target.connections > 0 ? " It has \(target.connections) connected client\(target.connections == 1 ? "" : "s")." : ""
                return "Would \(options.force ? "force-" : "")kill \(target.processName) (PID \(target.pid)) on :\(target.port).\(clients)"
            }.joined(separator: "\n")
            return finish(&report, action: "would-kill", exit: CLIExit.ok, text: (notes + [text]).joined(separator: "\n"))
        }

        var outcome = kill(targets, options: options, report: &report)
        if !notes.isEmpty {
            outcome = Outcome(report: outcome.report, text: (notes + [outcome.text]).joined(separator: "\n"), toStderr: outcome.toStderr)
        }
        return outcome
    }

    /// Every distinct process on the port, or the one pid asked for.
    public static func select(from ports: [PortInfo], options: CLICommand.KillOptions) -> [PortInfo] {
        var seenPids = Set<Int>()
        return ports.filter { port in
            let matches = options.pid.map { $0 == port.pid } ?? (port.port == options.port)
            guard matches, !seenPids.contains(port.pid) else { return false }
            seenPids.insert(port.pid)
            return true
        }
    }

    private static func kill(_ targets: [PortInfo], options: CLICommand.KillOptions, report: inout Report) -> Outcome {
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

        let store = HistoryManager.appStore()
        let killedBy = report.caller.map { "\($0.described) via CLI" } ?? "CLI"
        for target in killed {
            store.addEntry(port: target.port, processName: target.processName, action: .killed,
                           owner: target.agentOwner?.name, killedBy: killedBy)
        }

        var lines = killed.map { "Killed \($0.processName) (PID \($0.pid)) on :\($0.port)." }
        lines += signalled.filter { stillRunning.contains($0.pid) }.map { "\($0.processName) (PID \($0.pid)) is still running. Try --force." }
        lines += failures.map { "Failed to kill \($0)" }
        report.reasons += failures

        if signalled.isEmpty {
            return finish(&report, action: "failed", exit: CLIExit.killFailed, text: lines.joined(separator: "\n"), toStderr: true)
        }
        if !stillRunning.isEmpty {
            return finish(&report, action: "still-running", exit: CLIExit.stillRunning, text: lines.joined(separator: "\n"))
        }
        return finish(&report, action: "killed", exit: CLIExit.ok, text: lines.joined(separator: "\n"))
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

    private static func finish(_ report: inout Report, action: String, exit: Int32, text: String, toStderr: Bool = false) -> Outcome {
        report.action = action
        report.exitCode = exit
        return Outcome(report: report, text: text, toStderr: toStderr)
    }
}
