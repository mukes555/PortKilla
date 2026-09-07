import Foundation

// MARK: - ProcessKiller
public class ProcessKiller {

    public enum KillError: Error, LocalizedError {
        case invalidPid(Int)
        case permissionDenied(Int)
        case identityMismatch(pid: Int, expected: String, actual: String)
        case unknownError(String)

        public var errorDescription: String? {
            switch self {
            case .invalidPid(let pid):
                return "Invalid PID \(pid)"
            case .permissionDenied(let pid):
                return "No permission to kill PID \(pid)"
            case .identityMismatch(let pid, _, let actual):
                return "PID \(pid) now belongs to '\(actual)': refresh and retry"
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
    public func killProcess(pid: Int, force: Bool = false, killTree: Bool = false, expectedName: String? = nil) throws {
        // kill(0)/kill(-1) signal entire process groups: never allow them.
        guard pid > 0 else { throw KillError.invalidPid(pid) }

        if let expectedName {
            guard let actualName = currentProcessName(pid: pid) else {
                return // Already gone, nothing to do.
            }
            if !Self.namesMatch(expected: expectedName, actual: actualName) {
                throw KillError.identityMismatch(pid: pid, expected: expectedName, actual: actualName)
            }
        }

        if killTree {
            // One snapshot of the process tree for the whole walk. Enumerating
            // the table again at every node cost depth x (all processes)
            // syscalls, and a reparent race could make the recursion cycle.
            var seen: Set<Int> = [pid]
            killDescendants(of: pid, force: force, children: childrenByParent(), seen: &seen, depth: 0)
        }

        // The user explicitly chooses SIGKILL (force); a graceful kill must
        // never silently escalate, so a failed SIGTERM is reported, not forced.
        let signal = force ? SIGKILL : SIGTERM
        if kill(pid_t(pid), signal) == 0 {
            return
        }

        switch errno {
        case ESRCH:
            return // Process died in the meantime: mission accomplished.
        case EPERM:
            throw KillError.permissionDenied(pid)
        default:
            throw KillError.unknownError("kill(\(pid)) failed (errno \(errno))")
        }
    }

    /// Case-insensitive name match tolerant of lsof's ~9-char truncation.
    /// An empty expected name means "cannot verify" and never matches: an
    /// empty prefix would otherwise make the identity check always pass.
    public static func namesMatch(expected: String, actual: String) -> Bool {
        let expectedLower = expected.lowercased()
        let actualLower = actual.lowercased()
        guard !expectedLower.isEmpty, !actualLower.isEmpty else { return false }
        return actualLower.hasPrefix(expectedLower) || expectedLower.hasPrefix(actualLower)
    }

    private static let maxTreeDepth = 32

    /// Kills grandchildren before children before the caller signals the
    /// parent. Each child is checked against the name it had when the tree
    /// was captured, so a pid recycled during the walk fails the check
    /// instead of being signalled.
    private func killDescendants(of pid: Int, force: Bool, children: (Int) -> [(pid: Int, name: String)],
                                 seen: inout Set<Int>, depth: Int) {
        guard depth < Self.maxTreeDepth else { return }
        for child in children(pid) where !seen.contains(child.pid) {
            seen.insert(child.pid)
            killDescendants(of: child.pid, force: force, children: children, seen: &seen, depth: depth + 1)
            try? killProcess(pid: child.pid, force: force, expectedName: child.name)
        }
    }

    /// Children lookup from one native snapshot; pgrep per node only when
    /// libproc gave nothing (sandboxed or unexpected OS).
    private func childrenByParent() -> (Int) -> [(pid: Int, name: String)] {
        let processes = NativeScanner.processMap()
        guard !processes.isEmpty else {
            // pgrep gives pids only; an unverifiable name kills as before.
            return { Self.pgrepChildren(of: $0).map { (pid: $0, name: "") } }
        }

        var byParent: [Int: [(pid: Int, name: String)]] = [:]
        for (child, process) in processes {
            byParent[Int(process.ppid), default: []].append((pid: Int(child), name: process.name))
        }
        return { byParent[$0] ?? [] }
    }

    private static func pgrepChildren(of pid: Int) -> [Int] {
        // pgrep exits 1 with no children
        let output = (try? CommandRunner.run(
            "/usr/bin/pgrep", ["-P", "\(pid)"], timeout: 2.0, allowedExitCodes: [0, 1]
        )) ?? ""
        return output.components(separatedBy: .newlines).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
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
    /// SZOMB from sys/proc.h: exited, not yet reaped by its parent. kill(2)
    /// still succeeds on a zombie, so the CLI would otherwise wait the full
    /// timeout and report a dead process as "still running".
    private static let zombieStatus: UInt32 = 5

    public func isProcessRunning(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }

        if let bsd = NativeScanner.bsdInfo(Int32(pid)) {
            return bsd.pbi_status != Self.zombieStatus
        }
        if kill(pid_t(pid), 0) == 0 {
            return true
        }
        // EPERM means it exists but belongs to someone else.
        return errno == EPERM
    }
}
