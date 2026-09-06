import Foundation

/// Why PortKilla attributed a process the way it did: the ancestors it
/// walked, the markers it found, and which signal decided. `whois` prints
/// it, so a surprising owner can be checked without reading the code.
public struct AttributionEvidence: Encodable {
    public struct Ancestor: Encodable {
        public let pid: Int
        public let name: String
        /// "agent: Claude Code", "editor: Cursor", "barrier", or absent.
        public let role: String?
    }

    /// PORTKILLA_OWNER as found in the environment, before canonicalising.
    public let declaredOwner: String?
    public let declaredSession: String?
    /// From the parent upwards, ending with the ancestor that decided (or
    /// the barrier that stopped the walk).
    public let ancestry: [Ancestor]
    /// The allowlisted marker keys present, with their values.
    public let markers: [String: String]
    /// "declared" | "process tree" | "environment" | "none"
    public let decidedBy: String
    public let owner: AgentOwner?

    /// "zsh (800) -> claude (790) [agent: Claude Code]"
    public var ancestryLine: String {
        ancestry.map { ancestor in
            let role = ancestor.role.map { " [\($0)]" } ?? ""
            return "\(ancestor.name) (\(ancestor.pid))\(role)"
        }.joined(separator: " -> ")
    }

    /// "CLAUDECODE=1, CLAUDE_PID=790"
    public var markersLine: String {
        markers.keys.sorted().map { "\($0)=\(markers[$0]!)" }.joined(separator: ", ")
    }
}

extension AgentAttribution {

    /// The same decision `owner(ofPid:)` makes, with its working shown.
    public static func explain(pid: Int, in processes: ProcessTable,
                               environmentOf: EnvironmentLookup = liveEnvironment) -> AttributionEvidence {
        let environment = environmentOf(pid)
        let owner = owner(ofPid: pid, in: processes, environmentOf: environmentOf)
        let markers = environment.filter { AgentSignatures.markerKeys.contains($0.key) }
        let decidedBy: String
        switch owner?.source {
        case .declared: decidedBy = "declared"
        case .processTree: decidedBy = "process tree"
        case .environment: decidedBy = "environment"
        case nil: decidedBy = "none"
        }
        return AttributionEvidence(
            declaredOwner: environment[AgentSignatures.declaredOwnerKey],
            declaredSession: environment[AgentSignatures.declaredSessionKey],
            ancestry: ancestors(of: pid, in: processes),
            markers: markers,
            decidedBy: decidedBy,
            owner: owner
        )
    }

    /// The chain the tree walk sees, annotated, stopping where the walk
    /// stops: after a signature match or at a barrier.
    static func ancestors(of pid: Int, in processes: ProcessTable) -> [AttributionEvidence.Ancestor] {
        var chain: [AttributionEvidence.Ancestor] = []
        var current = processes.ppid(for: pid)
        var seen = Set<Int>()

        while let next = current, next > 1, !seen.contains(next), chain.count < maxDepth {
            seen.insert(next)
            let name = processes.name(for: next) ?? "?"
            if AgentSignatures.attributionBarriers.contains(name) {
                chain.append(.init(pid: next, name: name, role: "barrier"))
                break
            }
            let signature = processes.command(for: next).flatMap { match(command: $0, executableName: processes.name(for: next)) }
            let role = signature.map { "\($0.confidence == .agent ? "agent" : "editor"): \($0.name)" }
            chain.append(.init(pid: next, name: name, role: role))
            if signature != nil { break }
            current = processes.ppid(for: next)
        }
        return chain
    }
}
