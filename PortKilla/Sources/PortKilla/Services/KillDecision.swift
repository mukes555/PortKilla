import Foundation

/// The one answer every kill path asks before signalling: may this caller
/// stop that process? Agents (the CLI) can be refused; a person in the GUI
/// is only ever warned, because the human is the authority the guard exists
/// to protect.
enum KillDecision: Equatable {
    case allow
    case warn(String)
    case refuse(String)

    /// A person acting in the GUI. Warn when another agent's session still
    /// owns the target; never refuse.
    static func forHuman(target: AgentOwner?) -> KillDecision {
        guard let target, target.isLiveAgentSession else { return .allow }
        let running = target.sessionPid == nil ? "" : ", which is still running"
        return .warn("Started by \(target.described)\(running).")
    }

    /// An agent acting through the CLI. Refuse when the target belongs to a
    /// different agent, or to a different live session of the same agent.
    /// Unknown on either side never blocks: we don't refuse on a guess, and
    /// a person at a plain terminal is not an agent.
    static func forAgent(caller: AgentOwner?, target: AgentOwner?) -> KillDecision {
        guard let target, target.isLiveAgentSession, let caller else { return .allow }

        if caller.name != target.name {
            return .refuse("owned by \(target.described), not \(caller.described)")
        }
        if caller.isSameSession(as: target) == false {
            return .refuse("owned by another \(target.name) session (\(target.sessionId)), not yours (\(caller.sessionId))")
        }
        return .allow
    }

    /// Why the guard did or did not apply, for the CLI's report: an agent
    /// must be able to tell "checked and cleared" from "could not check".
    static func verdict(caller: AgentOwner?, target: AgentOwner?, forced: Bool) -> String {
        switch forAgent(caller: caller, target: target) {
        case .refuse: return forced ? "overridden" : "refused"
        case .warn: return "allowed"
        case .allow:
            if target?.isLiveAgentSession == true && caller == nil { return "not-evaluated: caller unknown" }
            if target == nil { return "not-evaluated: target unknown" }
            return "allowed"
        }
    }

    /// A line for bulk confirmations: "2 of these belong to running AI agent
    /// sessions." Nil when none do.
    static func liveAgentNote(for owners: [AgentOwner?]) -> String? {
        let live = owners.compactMap { $0 }.filter(\.isLiveAgentSession).count
        guard live > 0 else { return nil }
        return "\(live) of these belong\(live == 1 ? "s" : "") to running AI agent session\(live == 1 ? "" : "s")."
    }
}
