import Foundation

// MARK: - ProcessKiller
class ProcessKiller {

    enum KillError: Error, LocalizedError {
        case invalidPid(Int)
        case permissionDenied(Int)
        case identityMismatch(pid: Int, expected: String, actual: String)
        case unknownError(String)

        var errorDescription: String? {
            switch self {
            case .invalidPid(let pid):
                return "Invalid PID \(pid)"
            case .permissionDenied(let pid):
                return "No permission to kill PID \(pid)"
            case .identityMismatch(let pid, _, let actual):
                return "PID \(pid) now belongs to '\(actual)' — refresh and retry"
            case .unknownError(let message):
                return message
            }
        }
    }

    /// Kills a process by PID, optionally killing its children as well.
    ///
    /// Pass `expectedName` (the process name captured at scan time) whenever
    /// possible: PIDs get recycled, and the check refuses to signal a PID that
    /// now belongs to a different program.
    func killProcess(pid: Int, force: Bool = false, killTree: Bool = false, expectedName: String? = nil) throws {
        // kill(0)/kill(-1) signal entire process groups — never allow them.
        guard pid > 0 else { throw KillError.invalidPid(pid) }

        if let expectedName {
            guard let actualName = currentProcessName(pid: pid) else {
                return // Already gone — nothing to do.
            }
            // Prefix match in both directions because lsof truncates long names.
            let expected = expectedName.lowercased()
            let actual = actualName.lowercased()
            let sameProcess = actual.hasPrefix(expected) || expected.hasPrefix(actual)
            if !sameProcess {
                throw KillError.identityMismatch(pid: pid, expected: expectedName, actual: actualName)
            }
        }

        if killTree {
            for childPid in getChildPids(for: pid) {
                try? killProcess(pid: childPid, force: force, killTree: true)
            }
        }

        // The user explicitly chooses SIGKILL (force); a graceful kill must
        // never silently escalate, so a failed SIGTERM is reported, not forced.
        let signal = force ? SIGKILL : SIGTERM
        if kill(pid_t(pid), signal) == 0 {
            return
        }

        switch errno {
        case ESRCH:
            return // Process died in the meantime — mission accomplished.
        case EPERM:
            throw KillError.permissionDenied(pid)
        default:
            throw KillError.unknownError("kill(\(pid)) failed (errno \(errno))")
        }
    }

    private func getChildPids(for pid: Int) -> [Int] {
        // pgrep exits 1 when there are no children.
        let output = (try? CommandRunner.run(
            "/usr/bin/pgrep", ["-P", "\(pid)"], timeout: 2.0, allowedExitCodes: [0, 1]
        )) ?? ""

        return output.components(separatedBy: .newlines)
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Returns the executable base name currently running under `pid`,
    /// or nil if the PID is not alive.
    private func currentProcessName(pid: Int) -> String? {
        // ps exits 1 when the PID doesn't exist.
        let output = (try? CommandRunner.run(
            "/bin/ps", ["-p", "\(pid)", "-o", "comm="], timeout: 2.0, allowedExitCodes: [0, 1]
        )) ?? ""

        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty { return nil }
        return path.split(separator: "/").last.map(String.init) ?? path
    }

    /// Checks if a process is currently running
    func isProcessRunning(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }

        if kill(pid_t(pid), 0) == 0 {
            return true
        }
        // EPERM means it exists but belongs to someone else.
        return errno == EPERM
    }
}
