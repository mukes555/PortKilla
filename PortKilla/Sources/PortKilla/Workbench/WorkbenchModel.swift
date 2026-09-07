import Foundation
import PortKillaCore

/// The groupings the Workbench shows, as plain functions so they can be
/// tested without a window.
enum WorkbenchModel {

    struct ProjectGroup: Identifiable {
        let id: String
        let name: String
        let path: String?
        let ports: [PortInfo]
        var memoryKB: Int { ports.reduce(0) { $0 + $1.memorySizeKB } }
        var agents: [String] { Array(Set(ports.compactMap { $0.agentOwner?.name })).sorted() }
    }

    /// One group per working directory; ports without one share "No project".
    static func projects(from ports: [PortInfo]) -> [ProjectGroup] {
        let byPath = Dictionary(grouping: ports) { $0.projectPath ?? "" }
        return byPath.map { path, members in
            let name = path.isEmpty ? "No project" : (members.first?.projectName ?? (path as NSString).lastPathComponent)
            return ProjectGroup(id: path.isEmpty ? "(none)" : path, name: name, path: path.isEmpty ? nil : path,
                                ports: members.sorted { $0.port < $1.port })
        }
        .sorted { a, b in
            // Named projects first, then by size, so the busiest project is on top.
            if (a.path == nil) != (b.path == nil) { return a.path != nil }
            return a.memoryKB != b.memoryKB ? a.memoryKB > b.memoryKB : a.name < b.name
        }
    }

    struct AgentSession: Identifiable {
        enum Kind: Int {
            case live = 0
            case ended = 1
            case editor = 2
            case unattributed = 3
        }
        let id: String
        let title: String
        let subtitle: String
        let kind: Kind
        let owner: AgentOwner?
        let ports: [PortInfo]
    }

    /// One row per agent session, then ended sessions, editor terminals, and
    /// the servers nobody claims.
    static func agentSessions(from ports: [PortInfo]) -> [AgentSession] {
        var sessions: [String: [PortInfo]] = [:]
        var owners: [String: AgentOwner] = [:]
        for port in ports {
            let key = port.agentOwner.map(sessionKey) ?? "(unattributed)"
            sessions[key, default: []].append(port)
            if let owner = port.agentOwner, owners[key] == nil { owners[key] = owner }
        }
        return sessions.map { key, members -> AgentSession in
            let owner = owners[key]
            let kind: AgentSession.Kind
            if owner == nil { kind = .unattributed }
            else if owner?.confidence == .editorTerminal { kind = .editor }
            else if owner?.sessionEnded == true { kind = .ended }
            else { kind = .live }
            return AgentSession(id: key, title: title(for: owner), subtitle: subtitle(for: owner), kind: kind, owner: owner,
                                ports: members.sorted { $0.port < $1.port })
        }
        .sorted { a, b in
            if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
            return a.title != b.title ? a.title < b.title : a.subtitle < b.subtitle
        }
    }

    /// The badge counts, without building the groups.
    static func projectCount(of ports: [PortInfo]) -> Int {
        Set(ports.map { $0.projectPath ?? "" }).count
    }

    static func sessionCount(of ports: [PortInfo]) -> Int {
        Set(ports.map { $0.agentOwner.map(sessionKey) ?? "(unattributed)" }).count
    }

    /// Live sessions only, for the header: an ended session is not running.
    static func liveSessionCount(of ports: [PortInfo]) -> Int {
        Set(ports.compactMap(\.agentOwner).filter(\.isLiveAgentSession).map(sessionKey)).count
    }

    private static func sessionKey(_ owner: AgentOwner) -> String {
        if owner.sessionEnded { return "\(owner.name) (ended)" }
        if owner.confidence == .editorTerminal { return "\(owner.name) terminal" }
        return owner.sessionId
    }

    private static func title(for owner: AgentOwner?) -> String {
        guard let owner else { return "Unattributed" }
        if owner.confidence == .editorTerminal { return "\(owner.name) terminal" }
        return owner.name
    }

    private static func subtitle(for owner: AgentOwner?) -> String {
        guard let owner else { return "no agent above them, no markers, nothing declared" }
        if owner.confidence == .editorTerminal { return "started inside the editor, by a person or its agent" }
        if owner.sessionEnded { return "session ended; anyone may stop these" }
        var parts: [String] = []
        if let pid = owner.sessionPid { parts.append("session \(pid)") }
        if let key = owner.shortSessionKey { parts.append("id \(key)") }
        parts.append(owner.source == .declared ? "declared" : "from \(owner.source.rawValue)")
        return parts.joined(separator: " · ")
    }

    /// Ended sessions' servers: what "Clean up" stops.
    static func orphaned(_ ports: [PortInfo]) -> [PortInfo] {
        ports.filter { $0.agentOwner?.sessionEnded == true }
    }
}

/// Sortable, non-optional views of a port for the table's comparators.
extension PortInfo {
    var projectLabel: String { projectName ?? "" }
    var agentLabel: String { agentOwner?.label ?? "" }
    var managedLabel: String { managedBy?.short ?? "" }
    var ageLabel: String { age ?? "" }
}
