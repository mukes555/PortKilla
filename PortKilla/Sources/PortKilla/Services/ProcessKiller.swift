import Foundation

// MARK: - ProcessKiller
class ProcessKiller {

    enum KillError: Error {
        case permissionDenied
        case processNotFound
        case unknownError(String)
    }

    /// Kills a process by PID, optionally killing its children as well (process tree)
    func killProcess(pid: Int, force: Bool = false, killTree: Bool = false) throws {
        if killTree {
            // Find children first
            let children = getChildPids(for: pid)
            for childPid in children {
                // Recursively kill child's children too?
                // For simplicity, let's just kill direct children or recurse one level if needed.
                // But generally, killing the tree means killing everything rooted at PID.
                // Let's do a simple recursive call for safety.
                try? killProcess(pid: childPid, force: force, killTree: true)
            }
        }
    
        // Try the C-level kill function first, as it's more direct and reliable than spawning a Process
        let signal = force ? SIGKILL : SIGTERM

        // kill(pid, signal) returns 0 on success, -1 on error
        if kill(pid_t(pid), signal) == 0 {
            return
        }

        let errorCode = errno

        // If process not found (ESRCH), it's effectively dead
        if errorCode == ESRCH {
            return
        }

        // If SIGTERM failed and we haven't forced yet, try forcing
        if !force {
            if kill(pid_t(pid), SIGKILL) == 0 {
                return
            }
        }

        // If C-level kill failed, let's try the shell command as a fallback
        // This is useful if there are weird environment/path issues
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
        } catch {
            throw KillError.unknownError(error.localizedDescription)
        }
    }
    
    private func getChildPids(for pid: Int) -> [Int] {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-P", "\(pid)"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            let pids = output.components(separatedBy: .newlines)
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return pids
        } catch {
            return []
        }
    }

    /// Checks if a process is currently running
    func isProcessRunning(_ pid: Int) -> Bool {
        if kill(pid_t(pid), 0) == 0 {
            return true
        }

        switch errno {
        case EPERM:
            return true
        case ESRCH:
            return false
        default:
            return false
        }
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

}
