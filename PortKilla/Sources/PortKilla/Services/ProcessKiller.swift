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
        let task = Process()
        task.launchPath = "/bin/kill"
        task.arguments = force ? ["-9", "\(pid)"] : ["\(pid)"]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                // If standard kill fails, maybe try force kill automatically? 
                // For now, respect the flag.
                throw KillError.unknownError("Failed to kill process \(pid). Exit code: \(task.terminationStatus)")
            }
        } catch {
            throw KillError.unknownError(error.localizedDescription)
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
