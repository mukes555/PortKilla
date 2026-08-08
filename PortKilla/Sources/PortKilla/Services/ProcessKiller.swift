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
            if !Self.namesMatch(expected: expectedName, actual: actualName) {
                throw KillError.identityMismatch(pid: pid, expected: expectedName, actual: actualName)
            }
        }

        if killTree {
            // Capture each child's name at enumeration time so the recursive
            // kill still runs the PID-reuse identity check where possible.
            // A nil name (lookup failed) means "can't verify" — kill anyway,
            // preserving the original unconditional tree-kill behavior.
            for (childPid, childName) in getChildProcesses(for: pid) {
                try? killProcess(pid: childPid, force: force, killTree: true, expectedName: childName)
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

    /// Case-insensitive name match tolerant of lsof's ~9-char truncation.
    /// An empty expected name means "cannot verify" and never matches — an
    /// empty prefix would otherwise make the identity check always pass.
    static func namesMatch(expected: String, actual: String) -> Bool {
        let expectedLower = expected.lowercased()
        let actualLower = actual.lowercased()
        guard !expectedLower.isEmpty, !actualLower.isEmpty else { return false }
        return actualLower.hasPrefix(expectedLower) || expectedLower.hasPrefix(actualLower)
    }

    private func getChildProcesses(for pid: Int) -> [(pid: Int, name: String?)] {
        let children = NativeScanner.childPids(of: Int32(pid))
        if !children.isEmpty {
            return children.map { (Int($0), NativeScanner.processName($0)) }
        }

        // pgrep -l lists "pid name"; exits 1 with no children
        let output = (try? CommandRunner.run(
            "/usr/bin/pgrep", ["-lP", "\(pid)"], timeout: 2.0, allowedExitCodes: [0, 1]
        )) ?? ""

        return output.components(separatedBy: .newlines).compactMap { line -> (pid: Int, name: String?)? in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard let first = parts.first, let childPid = Int(first.trimmingCharacters(in: .whitespaces)) else {
                return nil
            }
            let name = parts.count > 1 ? String(parts[1]) : nil
            return (childPid, name)
        }
    }

    /// Returns the executable base name currently running under `pid`,
    /// or nil if the PID is not alive.
    private func currentProcessName(pid: Int) -> String? {
        guard isProcessRunning(pid) else { return nil }

        if let name = NativeScanner.processName(Int32(pid)) {
            return name
        }

        // Fallback: ps exits 1 when the PID doesn't exist
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
