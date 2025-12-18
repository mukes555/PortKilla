import Foundation

// MARK: - ProcessKiller
class ProcessKiller {

    enum KillError: Error {
        case permissionDenied
        case processNotFound
        case unknownError(String)
    }

    /// Kills a process by PID
    func killProcess(pid: Int, force: Bool = false) throws {
        // Log attempt
        print("ProcessKiller: Attempting to kill PID \(pid) (force: \(force))")
        
        // Try the C-level kill function first, as it's more direct and reliable than spawning a Process
        let signal = force ? SIGKILL : SIGTERM

        // kill(pid, signal) returns 0 on success, -1 on error
        if kill(pid_t(pid), signal) == 0 {
            print("ProcessKiller: Successfully sent signal \(signal) to PID \(pid)")
            return
        }
        
        let errorCode = errno
        print("ProcessKiller: C-level kill failed with error code: \(errorCode)")

        // If process not found (ESRCH), it's effectively dead
        if errorCode == ESRCH {
            print("ProcessKiller: Process \(pid) not found (already dead)")
            return
        }

        // If SIGTERM failed and we haven't forced yet, try forcing
        if !force { 
            print("ProcessKiller: SIGTERM failed, escalating to SIGKILL for PID \(pid)")
            if kill(pid_t(pid), SIGKILL) == 0 {
                return
            }
        }

        // If C-level kill failed, let's try the shell command as a fallback
        // This is useful if there are weird environment/path issues
        print("ProcessKiller: Falling back to shell command for PID \(pid)")
        let task = Process()
        task.launchPath = "/bin/kill"
        task.arguments = ["-9", "\(pid)"] // Force kill

        do {
            // Pipe output to avoid cluttering logs
            task.standardOutput = Pipe()
            task.standardError = Pipe()

            try task.run()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                throw KillError.unknownError("Failed to kill process \(pid).")
            }
            print("ProcessKiller: Shell kill command succeeded for PID \(pid)")
        } catch {
            print("ProcessKiller: Shell kill command failed: \(error)")
            throw KillError.unknownError(error.localizedDescription)
        }
    }

    /// Checks if a process is currently running
    func isProcessRunning(_ pid: Int) -> Bool {
        // kill(pid, 0) checks existence without sending a signal
        return kill(pid_t(pid), 0) == 0
    }

    /// Kills multiple processes
    func killProcesses(pids: [Int], force: Bool = false) -> [Int: Result<Void, Error>] {
        var results: [Int: Result<Void, Error>] = [:]

        for pid in pids {
            do {
                try killProcess(pid: pid, force: force)
                results[pid] = .success(())
            } catch {
                results[pid] = .failure(error)
            }
        }

        return results
    }

    /// Kills all Node.js processes
    func killAllNodeProcesses() throws {
        let scanner = PortScanner()
        let ports = scanner.scanActivePorts()
        let nodePorts = ports.filter { $0.type == .nodejs }
        let pids = nodePorts.map { $0.pid }

        let results = killProcesses(pids: pids)
        let failures = results.filter {
            if case .failure = $0.value { return true }
            return false
        }

        if !failures.isEmpty {
            throw KillError.unknownError("Failed to kill \(failures.count) processes")
        }
    }
}
