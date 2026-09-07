import Foundation

/// `portkilla reserve`, `release`, and `reservations`: leases on free ports,
/// so two agents about to start servers do not race for the same one.
public enum CLIReserve {

    public struct ReserveReport: Encodable {
        let schema = 1
        let action: String
        let port: Int
        let reservation: Reservation?
        let occupant: PortInfo?
        let reasons: [String]
        let exitCode: Int32
    }

    public static func reserve(_ options: CLICommand.ReserveOptions) -> Int32 {
        let report = performReserve(options)
        if options.json {
            return PortKillaCLI.printJSON(report) ? report.exitCode : CLIExit.internalError
        }
        switch report.action {
        case "reserved", "renewed":
            let lease = report.reservation!
            print("\(report.action.capitalized) :\(lease.port) as \(lease.describedHolder), \(lease.expiryDescription()). Start your server on it; `portkilla release \(lease.port)` when done.")
        default:
            PortKillaCLI.printError(report.reasons.joined(separator: "\n"))
        }
        return report.exitCode
    }

    public static func performReserve(_ options: CLICommand.ReserveOptions, store: ReservationStore = .appStore()) -> ReserveReport {
        let scan = PortKillaCLI.scan(refreshDocker: false)
        if let occupant = scan.ports.first(where: { $0.port == options.port }) {
            return ReserveReport(action: "in-use", port: options.port, reservation: nil, occupant: occupant,
                                 reasons: [":\(options.port) is in use by \(occupant.processName) (PID \(occupant.pid)); reservations are for free ports. Run `portkilla whois \(options.port)`."],
                                 exitCode: CLIExit.notFound)
        }
        let caller = scan.caller
        let renewing = store.reservation(for: options.port)?.isHeld(by: caller) == true
        let lease = Reservation(port: options.port, owner: caller?.name ?? Reservation.currentUser, sessionKey: caller?.sessionKey,
                                sessionPid: caller?.sessionPid, reason: options.reason, ttl: options.ttl)
        do {
            try store.reserve(lease, by: caller)
            return ReserveReport(action: renewing ? "renewed" : "reserved", port: options.port, reservation: lease, occupant: nil, reasons: [], exitCode: CLIExit.ok)
        } catch ReservationStore.Conflict.heldByAnother(let existing) {
            let why = ":\(options.port) is reserved by \(existing.describedHolder) \(existing.expiryDescription())" + (existing.reason.map { ", for \($0)" } ?? "") + ". Wait, ask, or pick another port with `portkilla free-port`."
            return ReserveReport(action: "refused", port: options.port, reservation: existing, occupant: nil, reasons: [why], exitCode: CLIExit.refused)
        } catch {
            return ReserveReport(action: "failed", port: options.port, reservation: nil, occupant: nil, reasons: [error.localizedDescription], exitCode: CLIExit.internalError)
        }
    }

    public struct ReleaseReport: Encodable {
        let schema = 1
        let action: String
        let port: Int
        let reservation: Reservation?
        let exitCode: Int32
    }

    public static func release(port: Int, force: Bool, json: Bool) -> Int32 {
        let report = performRelease(port: port, force: force)
        if json {
            return PortKillaCLI.printJSON(report) ? report.exitCode : CLIExit.internalError
        }
        switch report.action {
        case "released":
            print("Released :\(port).")
        case "refused":
            let lease = report.reservation!
            PortKillaCLI.printError(":\(port) is reserved by \(lease.describedHolder) \(lease.expiryDescription()); pass --force to release someone else's lease.")
        default:
            print(":\(port) is not reserved.")
        }
        return report.exitCode
    }

    public static func performRelease(port: Int, force: Bool, store: ReservationStore = .appStore()) -> ReleaseReport {
        let caller = PortKillaCLI.callerIdentity()
        switch store.release(port: port, by: caller, force: force) {
        case .released(let lease):
            return ReleaseReport(action: "released", port: port, reservation: lease, exitCode: CLIExit.ok)
        case .heldByAnother(let lease):
            return ReleaseReport(action: "refused", port: port, reservation: lease, exitCode: CLIExit.refused)
        case .none:
            return ReleaseReport(action: "not-reserved", port: port, reservation: nil, exitCode: CLIExit.notFound)
        }
    }

    public static func list(json: Bool, store: ReservationStore = .appStore()) -> Int32 {
        let leases = store.all()
        if json {
            return PortKillaCLI.printJSON(leases) ? CLIExit.ok : CLIExit.internalError
        }
        if leases.isEmpty {
            print("No reserved ports.")
            return CLIExit.ok
        }
        if PortKillaCLI.stdoutIsTerminal {
            print("PORT   HELD BY                       EXPIRES                        REASON")
        }
        for lease in leases {
            print([
                ":\(lease.port)".padding(toLength: 7, withPad: " ", startingAt: 0),
                lease.describedHolder.padding(toLength: 30, withPad: " ", startingAt: 0),
                lease.expiryDescription().padding(toLength: 31, withPad: " ", startingAt: 0),
                lease.reason ?? "",
            ].joined())
        }
        return CLIExit.ok
    }
}
