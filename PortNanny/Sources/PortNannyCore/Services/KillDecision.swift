import Foundation

/// The one answer every kill path asks before signalling: may this caller
/// stop that process? Agents (the CLI) can be refused; a person in the GUI
/// is only ever warned, because the human is the authority the guard exists
/// to protect.
public enum KillDecision: Equatable {
    case allow
    case warn(String)
    case refuse(String)

    public var isRefusal: Bool {
        if case .refuse = self { return true }
        return false
    }

    /// A person acting in the GUI. Warn when another agent's session still
    /// owns the target; never refuse.
    public static func forHuman(target: AgentOwner?) -> KillDecision {
        guard let target, target.isLiveAgentSession else { return .allow }
        let running = target.sessionPid == nil ? "" : ", which is still running"
        return .warn("Started by \(target.described)\(running).")
    }

    /// An agent acting through the CLI. Refuse when the target belongs to a
    /// different agent, to a different live session of the same agent, or
    /// to nobody PortNanny can name: an unattributed server is most likely a
    /// person's, and the agent can ask. An unknown caller never blocks (a
    /// person at a plain terminal is not an agent). An editor terminal is
    /// treated as a person too, except against another agent's running
    /// server: the editor's own agent (Copilot, Cascade) leaves no marker,
    /// and a person only has to add --force.
    public static func forAgent(caller: AgentOwner?, target: AgentOwner?, refusesUnclaimed: Bool = Policy.refusesUnclaimedServers) -> KillDecision {
        guard let caller else { return .allow }
        guard let target else {
            let isIdentifiedAgent = caller.confidence == .agent
            guard isIdentifiedAgent, refusesUnclaimed else { return .allow }
            return .refuse("not attributed to any agent; if it is yours, start it with PORTNANNY_OWNER set, or ask the user")
        }
        guard target.isLiveAgentSession else { return .allow }

        if caller.name != target.name {
            let fromTerminal = caller.confidence == .editorTerminal ? "; commands from an editor terminal may come from its agent, add --force if you are the person" : ""
            return .refuse("owned by \(target.described), not \(caller.described)\(fromTerminal)")
        }
        let sameSession = caller.isSameSession(as: target)
        if sameSession == false {
            return .refuse("owned by another \(target.name) session (\(target.sessionId)), not yours (\(caller.sessionId))")
        }
        // The target's session is known and the caller's is not: a name alone
        // is not enough to claim it (anyone can export a name).
        if sameSession == nil && target.hasKnownSession {
            return .refuse("owned by \(target.described) and your \(caller.name) session is unknown; export PORTNANNY_SESSION (or run from the agent's own shell) so PortNanny can tell it is you")
        }
        return .allow
    }

    /// A lease on the port by someone else: agents are refused, people warned.
    public static func forReservation(caller: AgentOwner?, reservation: Reservation?, asAgent: Bool) -> KillDecision {
        guard let reservation, !reservation.isHeld(by: caller) else { return .allow }
        let what = "reserved by \(reservation.describedHolder) \(reservation.expiryDescription())" + (reservation.reason.map { ", for \($0)" } ?? "")
        if asAgent, caller?.confidence == .agent {
            return .refuse(what + "; wait, ask, or pick another port with `portnanny free-port`")
        }
        return .warn("The port is \(what).")
    }

    /// Why the guard did or did not apply, for the CLI's report: an agent
    /// must be able to tell "checked and cleared" from "could not check".
    public static func verdict(caller: AgentOwner?, target: AgentOwner?, forced: Bool) -> String {
        switch forAgent(caller: caller, target: target) {
        case .refuse: return forced ? "overridden" : "refused"
        case .warn: return "allowed"
        case .allow:
            if target?.isLiveAgentSession == true && caller == nil { return "not-evaluated: caller unknown" }
            if target == nil {
                if caller == nil { return "not-evaluated: target unknown" }
                if caller?.confidence != .agent { return "allowed: caller is not an agent" }
                return Policy.refusesUnclaimedServers ? "allowed" : "allowed: unclaimed guard off"
            }
            return "allowed"
        }
    }

    /// A line for bulk confirmations: "2 of these belong to running AI agent
    /// sessions." Nil when none do.
    public static func liveAgentNote(for owners: [AgentOwner?]) -> String? {
        let live = owners.compactMap { $0 }.filter(\.isLiveAgentSession).count
        guard live > 0 else { return nil }
        return "\(live) of these belong\(live == 1 ? "s" : "") to running AI agent session\(live == 1 ? "" : "s")."
    }
}
