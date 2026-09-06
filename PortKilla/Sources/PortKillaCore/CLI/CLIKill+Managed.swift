import Foundation

/// How `kill` treats a listener with a supervisor: stop the supervisor
/// (reloaders and masters), run the runtime's own stop verb (pm2, launchd,
/// Docker), or, with --force, kill the listener anyway. A plain kill of a
/// supervised process frees the port for a second and reports success.
extension CLIKill {

    struct Plan {
        let target: PortInfo
        /// The process to signal, and the name to verify before signalling.
        let signalPid: Int
        let signalName: String
        let killTree: Bool
        /// A command that replaces the signal: resolved argv, and its display form.
        let command: [String]?
        let commandText: String?
        /// "stop nodemon (PID 700) instead of node (PID 812) on :3000, because ..."
        let substitution: String?
        /// Why nothing can be done here.
        let blocked: String?

        static func plain(_ target: PortInfo) -> Plan {
            Plan(target: target, signalPid: target.pid, signalName: target.processName, killTree: false,
                 command: nil, commandText: nil, substitution: nil, blocked: nil)
        }

        static func blocked(_ target: PortInfo, _ reason: String) -> Plan {
            Plan(target: target, signalPid: target.pid, signalName: target.processName, killTree: false,
                 command: nil, commandText: nil, substitution: nil, blocked: reason)
        }
    }

    static func plan(for target: PortInfo, force: Bool, table: ProcessTable,
                     resolve: (String) -> String? = { ToolLocator.resolve($0) }) -> Plan {
        guard let managed = target.managedBy else { return .plain(target) }
        let subject = "\(target.processName) (PID \(target.pid)) on :\(target.port)"

        // Docker's backend process is never the thing to kill; --force means
        // SIGKILL for the container, not for Docker Desktop.
        if managed.kind == .docker {
            guard var argv = managed.stopArguments, let name = argv.last else {
                return .blocked(target, "\(subject) is published by Docker Desktop for a container `docker ps` can name; PortKilla does not kill Docker itself.")
            }
            if force { argv = ["docker", "kill", "--", name] }
            let text = argv.map(ManagedRuntime.shellQuoted).joined(separator: " ")
            guard let tool = resolve(argv[0]) else {
                return .blocked(target, "\(subject) is \(managed.label). Run `\(text)` (docker is not on PATH here).")
            }
            argv[0] = tool
            return Plan(target: target, signalPid: target.pid, signalName: target.processName, killTree: false, command: argv, commandText: text,
                        substitution: "run `\(text)` instead of killing \(subject), because \(managed.consequence)", blocked: nil)
        }
        guard !force else { return .plain(target) }

        switch managed.kind {
        case .docker:
            return .plain(target)
        case .reloader:
            guard let supervisor = managed.supervisorPid, let name = managed.supervisorName ?? table.name(for: supervisor) else { return .plain(target) }
            return Plan(target: target, signalPid: supervisor, signalName: name, killTree: true, command: nil, commandText: nil,
                        substitution: "stop \(managed.label) instead of \(subject), because \(managed.consequence)", blocked: nil)
        case .pm2, .launchd:
            guard var argv = managed.stopArguments, let text = managed.stopCommand else {
                return .blocked(target, "\(subject) is managed by \(managed.label) and \(managed.consequence). Pass --force to kill it anyway.")
            }
            guard let tool = resolve(argv[0]) else {
                return .blocked(target, "\(subject) is managed by \(managed.label) and \(managed.consequence). Run `\(text)` (\(argv[0]) is not on PATH here), or pass --force to kill it anyway.")
            }
            argv[0] = tool
            return Plan(target: target, signalPid: target.pid, signalName: target.processName, killTree: false, command: argv, commandText: text,
                        substitution: "run `\(text)` instead of killing \(subject), because \(managed.consequence)", blocked: nil)
        }
    }

    static func execute(_ plans: [Plan], options: CLICommand.KillOptions, report: inout Report) -> Outcome {
        let blocked = plans.compactMap(\.blocked)
        if !blocked.isEmpty {
            report.reasons += blocked
            return finish(&report, action: "managed", exit: CLIExit.managed, text: blocked.joined(separator: "\n"), toStderr: true)
        }

        let killer = ProcessKiller()
        var failures: [String] = []
        var signalled: [Plan] = []
        var commanded: [Plan] = []
        for plan in plans {
            if let command = plan.command {
                do {
                    _ = try CommandRunner.run(command[0], Array(command.dropFirst()), timeout: 20)
                    commanded.append(plan)
                    report.stoppedVia.append(plan.commandText ?? command.joined(separator: " "))
                } catch {
                    failures.append("`\(plan.commandText ?? "")` failed: \(error.localizedDescription)")
                }
                continue
            }
            do {
                try killer.killProcess(pid: plan.signalPid, force: options.force, killTree: plan.killTree, expectedName: plan.signalName)
                signalled.append(plan)
                if plan.signalPid != plan.target.pid {
                    report.stoppedVia.append("\(plan.signalName) (PID \(plan.signalPid))")
                }
            } catch {
                failures.append("\(plan.signalName) (PID \(plan.signalPid)): \(error.localizedDescription)")
            }
        }

        // A supervisor's child may take a moment longer than the supervisor.
        let awaited = signalled.flatMap { [$0.signalPid, $0.target.pid] }
        let stillRunning = waitForExit(awaited, timeout: PortManager.exitTimeout(force: options.force) + 1, killer: killer)
        // `docker stop` alone waits up to ten seconds for a graceful exit.
        let stillListening = ManagedRuntime.waitForPortsFree(commanded.map(\.target.port), timeout: 12)

        let killed = signalled.filter { !stillRunning.contains($0.signalPid) && !stillRunning.contains($0.target.pid) }
        let stopped = commanded.filter { !stillListening.contains($0.target.port) }
        record(killed + stopped, report: report)

        var lines = killed.map { plan -> String in
            let target = plan.target
            let leftover = options.orphaned ? " (\(target.agentOwner?.label ?? "orphaned"))" : ""
            if plan.signalPid != target.pid {
                return "Stopped \(plan.signalName) (PID \(plan.signalPid)), and with it \(target.processName) (PID \(target.pid)) on :\(target.port)."
            }
            return "Killed \(target.processName) (PID \(target.pid)) on :\(target.port)\(leftover)."
        }
        lines += stopped.map { "Stopped \($0.target.managedBy?.label ?? "") with `\($0.commandText ?? "")`; :\($0.target.port) is free." }
        lines += signalled.filter { stillRunning.contains($0.signalPid) || stillRunning.contains($0.target.pid) }
            .map { "\($0.target.processName) (PID \($0.target.pid)) is still running. Try --force." }
        lines += commanded.filter { stillListening.contains($0.target.port) }
            .map { ":\($0.target.port) is still in use after `\($0.commandText ?? "")`." }
        lines += failures.map { "Failed to kill \($0)" }
        report.reasons += failures

        let text = lines.joined(separator: "\n")
        if signalled.isEmpty && commanded.isEmpty {
            return finish(&report, action: "failed", exit: CLIExit.killFailed, text: text, toStderr: true)
        }
        if !stillRunning.isEmpty || !stillListening.isEmpty {
            return finish(&report, action: "still-running", exit: CLIExit.stillRunning, text: text)
        }
        let action = signalled.isEmpty ? "stopped" : "killed"
        return finish(&report, action: action, exit: CLIExit.ok, text: text)
    }

    private static func record(_ done: [Plan], report: Report) {
        let store = HistoryManager.appStore()
        let actor = report.caller.map { "\($0.described) via CLI" } ?? "CLI"
        for plan in done {
            let how = plan.commandText.map { " (\($0))" } ?? ""
            store.addEntry(port: plan.target.port, processName: plan.target.processName, action: .killed,
                           owner: plan.target.agentOwner?.name, killedBy: actor + how)
        }
    }
}
