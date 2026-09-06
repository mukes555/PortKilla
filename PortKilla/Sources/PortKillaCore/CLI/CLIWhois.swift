import Foundation

/// `portkilla whois`: everything PortKilla knows about what is on a port,
/// including why it attributed it the way it did and what `kill` would do
/// for this caller. `list` answers "what"; this answers "why".
public enum CLIWhois {

    public struct Report: Encodable {
        let schema = 1
        let port: Int?
        let pid: Int?
        let caller: AgentOwner?
        let targets: [Dossier]
        let exitCode: Int32
    }

    public struct Dossier: Encodable {
        let port: Int
        let proto: String
        let bindAddress: String?
        let pid: Int
        let processName: String
        let command: String
        let user: String
        let type: PortInfo.PortType
        let age: String?
        let projectName: String?
        let projectPath: String?
        let containerName: String?
        let connections: Int
        let children: [PortInfo.ProcessInfo]?
        let agentOwner: AgentOwner?
        let managedBy: ManagedRuntime?
        let evidence: AttributionEvidence
        /// What `kill` would do for the calling process, and why.
        let verdict: String
        let reason: String?
        /// The target runs in the caller's working directory, above it, or below it.
        let sameProject: Bool
    }

    public static func run(_ options: CLICommand.WhoisOptions) -> Int32 {
        let report = perform(options)
        if options.json {
            return PortKillaCLI.printJSON(report) ? report.exitCode : CLIExit.internalError
        }
        if report.targets.isEmpty {
            PortKillaCLI.printError(text(for: report))
        } else {
            print(text(for: report))
        }
        return report.exitCode
    }

    public static func perform(_ options: CLICommand.WhoisOptions,
                               cwd: String = FileManager.default.currentDirectoryPath) -> Report {
        let scan = PortKillaCLI.scan(refreshDocker: true)
        var selection = CLICommand.KillOptions()
        selection.port = options.port
        selection.pid = options.pid
        let targets = CLIKill.select(from: scan.ports, options: selection)
        let dossiers = targets.map { dossier(for: $0, caller: scan.caller, table: scan.table, cwd: cwd) }
        return Report(port: options.port, pid: options.pid, caller: scan.caller, targets: dossiers,
                      exitCode: dossiers.isEmpty ? CLIExit.notFound : CLIExit.ok)
    }

    static func dossier(for port: PortInfo, caller: AgentOwner?, table: ProcessTable, cwd: String) -> Dossier {
        let decision = KillDecision.forAgent(caller: caller, target: port.agentOwner)
        var reason: String?
        if case .refuse(let why) = decision { reason = why }
        return Dossier(
            port: port.port, proto: port.proto, bindAddress: port.bindAddress, pid: port.pid,
            processName: port.processName, command: port.command, user: port.user, type: port.type,
            age: port.age, projectName: port.projectName, projectPath: port.projectPath,
            containerName: port.containerName, connections: port.connections, children: port.children,
            agentOwner: port.agentOwner,
            managedBy: port.managedBy,
            evidence: evidence(for: port, table: table),
            verdict: KillDecision.verdict(caller: caller, target: port.agentOwner, forced: false),
            reason: reason,
            sameProject: CLIKill.isSameProject(port.projectPath, cwd: cwd)
        )
    }

    /// The scanner gives a Docker-fronted port no owner on purpose (the
    /// container owns it, not whoever launched Docker Desktop); the evidence
    /// says so instead of showing markers that would suggest otherwise.
    static func evidence(for port: PortInfo, table: ProcessTable) -> AttributionEvidence {
        let raw = AgentAttribution.explain(pid: port.pid, in: table)
        let isDockerFronted = port.containerName != nil || port.type == .docker
        guard isDockerFronted else { return raw }
        return AttributionEvidence(declaredOwner: raw.declaredOwner, declaredSession: raw.declaredSession,
                                   ancestry: raw.ancestry, markers: raw.markers, decidedBy: "docker", owner: nil)
    }

    public static func text(for report: Report) -> String {
        guard !report.targets.isEmpty else {
            return report.pid.map { "PID \($0) is not listening on any port." } ?? "Nothing is listening on :\(report.port ?? 0)."
        }
        return report.targets.map(text(for:)).joined(separator: "\n\n")
    }

    static func text(for dossier: Dossier) -> String {
        var lines: [String] = []
        let bind = dossier.bindAddress.map { " (\($0))" } ?? ""
        let age = dossier.age.map { ", up \($0)" } ?? ""
        let clients = dossier.connections > 0 ? ", \(dossier.connections) client\(dossier.connections == 1 ? "" : "s")" : ""
        lines.append(":\(dossier.port) \(dossier.proto)\(bind) \(dossier.processName), PID \(dossier.pid), \(dossier.type.rawValue)\(age)\(clients)")
        lines.append(row("command", dossier.command))
        lines.append(row("user", dossier.user))
        if let name = dossier.projectName ?? dossier.projectPath {
            let path = dossier.projectPath.map { " (\($0))" } ?? ""
            let same = dossier.sameProject ? ", your working directory" : ""
            lines.append(row("project", "\(name)\(path)\(same)"))
        }
        if let container = dossier.containerName {
            lines.append(row("container", container))
        }
        if let children = dossier.children, !children.isEmpty {
            lines.append(row("children", children.map { "\($0.name) (\($0.pid))" }.joined(separator: ", ")))
        }
        lines += ownerLines(dossier)
        if let managed = dossier.managedBy {
            let verb = managed.stopCommand.map { "; stop it with `\($0)`" } ?? ""
            lines.append(row("managed by", "\(managed.label): \(managed.consequence)\(verb)"))
        }
        let why = dossier.reason.map { ": \($0)" } ?? ""
        lines.append(row("kill", "\(dossier.verdict)\(why)"))
        return lines.joined(separator: "\n")
    }

    private static func ownerLines(_ dossier: Dossier) -> [String] {
        var lines: [String] = []
        if let owner = dossier.agentOwner {
            let how = owner.source == .declared ? "declared via PORTKILLA_OWNER" : "from \(owner.source.rawValue)"
            let ended = owner.sessionEnded ? ", session ended" : ""
            let kind = owner.confidence == .editorTerminal ? " (editor terminal, by a person or an agent inside it)" : ""
            lines.append(row("owner", "\(owner.described), \(how)\(ended)\(kind)"))
        } else if dossier.evidence.decidedBy == "docker" {
            let what = dossier.containerName.map { "container \($0)" } ?? "Docker"
            lines.append(row("owner", "none: \(what) owns this port; any markers below belong to whoever launched Docker Desktop"))
        } else {
            lines.append(row("owner", "none: no agent above it, no markers, nothing declared"))
        }
        let evidence = dossier.evidence
        if !evidence.ancestry.isEmpty {
            lines.append(row("ancestry", evidence.ancestryLine))
        }
        if !evidence.markers.isEmpty {
            lines.append(row("markers", evidence.markersLine))
        }
        return lines
    }

    private static func row(_ label: String, _ value: String) -> String {
        "  \(label.padding(toLength: 10, withPad: " ", startingAt: 0)) \(value)"
    }
}
