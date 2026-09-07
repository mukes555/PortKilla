import Foundation

/// A lease on a free port: "I am about to start something here". It keeps
/// `free-port` from handing the port to someone else and makes a kill on it
/// a refusal for other agents, until it expires or the holder releases it.
/// Leases live in the shared preference domain, so the CLI and the app see
/// the same ones.
public struct Reservation: Codable, Equatable, Identifiable {
    public var id: Int { port }
    public let port: Int
    /// Display name of the holder: an agent's name, or the user name.
    public let owner: String
    public let sessionKey: String?
    public let sessionPid: Int?
    public let reason: String?
    public let createdAt: Date
    public let expiresAt: Date

    public static let defaultTTL: TimeInterval = 10 * 60
    public static let maxTTL: TimeInterval = 24 * 60 * 60

    public init(port: Int, owner: String, sessionKey: String? = nil, sessionPid: Int? = nil, reason: String? = nil,
                createdAt: Date = Date(), ttl: TimeInterval = Reservation.defaultTTL) {
        self.port = port
        self.owner = owner
        self.sessionKey = sessionKey
        self.sessionPid = sessionPid
        self.reason = reason
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(min(max(ttl, 1), Reservation.maxTTL))
    }

    public func isExpired(at now: Date = Date()) -> Bool {
        expiresAt <= now
    }

    /// The holder as the guard sees it.
    public var holder: AgentOwner {
        AgentOwner(name: owner, sessionPid: sessionPid, sessionKey: sessionKey, source: .declared)
    }

    /// "Claude Code (session 56034)" or "mbp"
    public var describedHolder: String {
        holder.described
    }

    /// True when `caller` is the one who took the lease: same name, and the
    /// same session where both know theirs.
    public func isHeld(by caller: AgentOwner?, user: String = Reservation.currentUser) -> Bool {
        guard let caller else { return owner == user }
        guard caller.name == owner else { return false }
        return caller.isSameSession(as: holder) ?? true
    }

    /// "until 12:30 (8m left)"
    public func expiryDescription(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let left = max(0, Int(expiresAt.timeIntervalSince(now)))
        return "until \(formatter.string(from: expiresAt)) (\(Reservation.describe(seconds: left)) left)"
    }

    enum CodingKeys: String, CodingKey {
        case port, owner, sessionKey, sessionPid, reason, createdAt, expiresAt
    }

    private static let iso = ISO8601DateFormatter()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        port = try container.decode(Int.self, forKey: .port)
        owner = try container.decode(String.self, forKey: .owner)
        sessionKey = try container.decodeIfPresent(String.self, forKey: .sessionKey)
        sessionPid = try container.decodeIfPresent(Int.self, forKey: .sessionPid)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        let created = try container.decode(String.self, forKey: .createdAt)
        let expires = try container.decode(String.self, forKey: .expiresAt)
        guard let createdDate = Reservation.iso.date(from: created), let expiresDate = Reservation.iso.date(from: expires) else {
            throw DecodingError.dataCorruptedError(forKey: .createdAt, in: container, debugDescription: "not an ISO 8601 date")
        }
        createdAt = createdDate
        expiresAt = expiresDate
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(port, forKey: .port)
        try container.encode(owner, forKey: .owner)
        try container.encodeIfPresent(sessionKey, forKey: .sessionKey)
        try container.encodeIfPresent(sessionPid, forKey: .sessionPid)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encode(Reservation.iso.string(from: createdAt), forKey: .createdAt)
        try container.encode(Reservation.iso.string(from: expiresAt), forKey: .expiresAt)
    }

    public static var currentUser: String {
        ProcessInfo.processInfo.userName
    }

    /// "10m", "2h", "90s", "1d" to seconds; nil when unreadable or zero.
    public static func parseTTL(_ text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard let unit = trimmed.last else { return nil }
        let multipliers: [Character: TimeInterval] = ["s": 1, "m": 60, "h": 3600, "d": 86400]
        let digits = multipliers[unit] == nil ? trimmed : String(trimmed.dropLast())
        guard let number = Double(digits), number > 0 else { return nil }
        return number * (multipliers[unit] ?? 60)
    }

    public static func describe(seconds: Int) -> String {
        if seconds >= 3600 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
        if seconds >= 60 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }
}

/// The leases, pruned of expired ones on every read, in the shared domain.
public final class ReservationStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public static func appStore() -> ReservationStore {
        ReservationStore(defaults: UserDefaults(suiteName: HistoryManager.appSuiteName) ?? .standard)
    }

    public func all(now: Date = Date()) -> [Reservation] {
        load().filter { !$0.isExpired(at: now) }.sorted { $0.port < $1.port }
    }

    public func reservation(for port: Int, now: Date = Date()) -> Reservation? {
        all(now: now).first { $0.port == port }
    }

    public enum Conflict: Error, Equatable {
        case heldByAnother(Reservation)
    }

    /// Takes or renews a lease. A live lease held by someone else conflicts.
    @discardableResult
    public func reserve(_ reservation: Reservation, by caller: AgentOwner?, now: Date = Date()) throws -> Reservation {
        var current = all(now: now)
        if let existing = current.first(where: { $0.port == reservation.port }), !existing.isHeld(by: caller) {
            throw Conflict.heldByAnother(existing)
        }
        current.removeAll { $0.port == reservation.port }
        current.append(reservation)
        save(current)
        return reservation
    }

    /// Drops a lease. Another holder's lease needs `force`. False when there
    /// was nothing to release or it was not ours.
    public enum ReleaseOutcome: Equatable {
        case released(Reservation)
        case heldByAnother(Reservation)
        case none
    }

    public func release(port: Int, by caller: AgentOwner?, force: Bool = false, now: Date = Date()) -> ReleaseOutcome {
        var current = all(now: now)
        guard let existing = current.first(where: { $0.port == port }) else { return .none }
        if !existing.isHeld(by: caller) && !force { return .heldByAnother(existing) }
        current.removeAll { $0.port == port }
        save(current)
        return .released(existing)
    }

    /// Ports another live lease keeps off the table for `caller`.
    public func portsReservedByOthers(for caller: AgentOwner?, now: Date = Date()) -> Set<Int> {
        Set(all(now: now).filter { !$0.isHeld(by: caller) }.map(\.port))
    }

    private func load() -> [Reservation] {
        guard let data = defaults.data(forKey: DefaultsKey.reservations),
              let items = try? JSONDecoder().decode([Reservation].self, from: data) else { return [] }
        return items
    }

    private func save(_ reservations: [Reservation]) {
        if reservations.isEmpty {
            defaults.removeObject(forKey: DefaultsKey.reservations)
        } else if let data = try? JSONEncoder().encode(reservations) {
            defaults.set(data, forKey: DefaultsKey.reservations)
        }
    }
}
