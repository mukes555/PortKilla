import Foundation

// MARK: - Kill flows
// Every product-facing kill runs the same pipeline: signal on a background
// queue (identity-checked), wait for the exit event, then report on main.
extension PortManager {

    /// Event-driven wait for process exits (DispatchSourceProcess) instead of
    /// polling sleeps, with a final liveness sweep to catch processes that
    /// died before the kernel source was armed. Call from a background queue.
    func waitForExit(pids: [Int], timeout: TimeInterval = 1.0) -> Set<Int> {
        let condition = NSCondition()
        var dead = Set<Int>()
        var sources: [DispatchSourceProcess] = []
        let queue = DispatchQueue(label: "com.portkilla.exit-wait")

        condition.lock()
        for pid in pids {
            guard killer.isProcessRunning(pid) else {
                dead.insert(pid)
                continue
            }
            let source = DispatchSource.makeProcessSource(identifier: pid_t(pid), eventMask: .exit, queue: queue)
            source.setEventHandler {
                condition.lock()
                dead.insert(pid)
                condition.signal()
                condition.unlock()
            }
            source.activate()
            sources.append(source)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while dead.count < pids.count {
            if !condition.wait(until: deadline) { break }
        }
        condition.unlock()

        sources.forEach { $0.cancel() }
        // Drain the source queue so no exit handler is still mutating `dead`
        // while the sweep below reads/writes it (they share the condition lock,
        // but the sweep must not run concurrently with a queued handler).
        queue.sync { }

        // Sweep for exits that raced the source activation — under the lock,
        // serialized against any handler that fired at the deadline boundary.
        condition.lock()
        for pid in pids where !dead.contains(pid) && !killer.isProcessRunning(pid) {
            dead.insert(pid)
        }
        let result = dead
        condition.unlock()
        return result
    }

    /// Shared single-target pipeline; `subject` appears in user-facing messages.
    private func performSingleKill(
        pid: Int,
        expectedName: String,
        subject: String,
        force: Bool,
        killTree: Bool = false,
        errorContext: String,
        onKilled: @escaping () -> Void,
        onNotTerminated: (() -> Void)? = nil
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.killer.killProcess(pid: pid, force: force, killTree: killTree, expectedName: expectedName)
                let died = self.waitForExit(pids: [pid]).contains(pid)

                DispatchQueue.main.async {
                    if died {
                        self.lastErrorMessage = nil
                        onKilled()
                    } else {
                        let hint = force ? "" : " Option+click to force kill (SIGKILL)."
                        self.lastErrorMessage = "\(subject) did not terminate.\(hint)"
                        onNotTerminated?()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastErrorMessage = self.formatError(error, context: errorContext)
                    self.showToast(self.lastErrorMessage ?? "Kill failed")
                }
            }
        }
    }

    /// Kills a specific port
    func killPort(_ portInfo: PortInfo, force: Bool = false, killTree: Bool = false) {
        performSingleKill(
            pid: portInfo.pid,
            expectedName: portInfo.processName,
            subject: ":\(portInfo.port)",
            force: force,
            killTree: killTree,
            errorContext: "Kill failed for :\(portInfo.port)",
            onKilled: { [weak self] in
                guard let self = self else { return }
                // Optimistically remove for instant feedback; a refresh follows
                self.activePorts.removeAll { $0.id == portInfo.id }
                self.showToast("\(killTree ? "Killed Tree" : "Killed") :\(portInfo.port)")
                HistoryManager.shared.addEntry(
                    port: portInfo.port, processName: portInfo.processName, action: .killed
                )
                self.scheduleRefresh()
            },
            onNotTerminated: { [weak self] in
                self?.showToast("Kill failed for :\(portInfo.port)")
                // Slow shutdowns are common — notify when it finally frees
                self?.pendingFreeNotifications.insert(portInfo.port)
            }
        )
    }

    /// Kills whatever listens on a port number (used by the URL scheme).
    /// Scans fresh so it works even when the cached list is stale.
    /// `respectProtected` refuses to kill a protected process — always true for
    /// link-initiated kills so a webpage can't terminate the user's IDE/tools.
    func killPortNumber(_ portNumber: Int, force: Bool = false, respectProtected: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let table = ProcessTable.capture()
            // Fresh scanner: the shared one's cwd cache is not thread-safe
            // against a concurrently running timer refresh.
            let ports = (try? PortScanner().scanActivePorts(processes: table)) ?? []

            guard let target = ports.first(where: { $0.port == portNumber }) else {
                DispatchQueue.main.async {
                    self.showToast(":\(portNumber) is not in use")
                }
                return
            }

            if respectProtected && self.isProtectedProcessName(target.processName) {
                DispatchQueue.main.async {
                    self.showToast(":\(portNumber) is protected — not killed")
                }
                return
            }
            self.killPort(target, force: force)
        }
    }

    /// Kills an arbitrary process (used for children in the process tree).
    func killProcess(pid: Int, name: String, force: Bool = false) {
        performSingleKill(
            pid: pid,
            expectedName: name,
            subject: name,
            force: force,
            errorContext: "Kill failed for \(name)",
            onKilled: { [weak self] in
                self?.showToast("Killed \(name)")
                self?.scheduleRefresh(after: 0.5)
            },
            onNotTerminated: { [weak self] in
                self?.showToast("Kill failed")
            }
        )
    }

    /// Kills a specific test process
    func killTestProcess(_ testInfo: TestProcessInfo, force: Bool = false) {
        performSingleKill(
            pid: testInfo.pid,
            expectedName: testInfo.processName,
            subject: testInfo.processName,
            force: force,
            errorContext: "Kill failed for \(testInfo.processName)",
            onKilled: { [weak self] in
                self?.activeTests.removeAll { $0.id == testInfo.id }
                self?.showToast("Killed \(testInfo.processName)")
            },
            onNotTerminated: { [weak self] in
                self?.showToast("Kill failed")
            }
        )
    }

    /// Kills several test processes in one pass (one background block, one
    /// verification wait).
    func killTestProcesses(_ tests: [TestProcessInfo], force: Bool = false) {
        if tests.isEmpty {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            for test in tests {
                try? self.killer.killProcess(pid: test.pid, force: force, expectedName: test.processName)
            }

            let dead = self.waitForExit(pids: tests.map { $0.pid })

            DispatchQueue.main.async {
                self.activeTests.removeAll { dead.contains($0.pid) }
                let failed = tests.count - dead.count
                if failed > 0 {
                    self.showToast("Killed \(dead.count), \(failed) failed")
                } else {
                    self.showToast("Killed \(dead.count) test process\(dead.count == 1 ? "" : "es")")
                }
            }
        }
    }

    func killPorts(_ ports: [PortInfo], force: Bool = false) {
        if ports.isEmpty {
            return
        }

        // Several ports can share one PID; kill each process once.
        var portsByPid: [Int: PortInfo] = [:]
        for port in ports where portsByPid[port.pid] == nil {
            portsByPid[port.pid] = port
        }
        let targets = Array(portsByPid.values)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            for target in targets {
                try? self.killer.killProcess(pid: target.pid, force: force, expectedName: target.processName)
            }

            let deadPids = self.waitForExit(pids: targets.map { $0.pid })
            let successCount = deadPids.count

            DispatchQueue.main.async {
                if successCount > 0 {
                    self.activePorts.removeAll { deadPids.contains($0.pid) }
                    self.lastErrorMessage = nil

                    let failureCount = targets.count - successCount
                    if failureCount > 0 {
                        self.showToast("Killed \(successCount), \(failureCount) failed")
                    } else {
                        self.showToast("Killed \(successCount) process\(successCount == 1 ? "" : "es")")
                    }

                    for port in ports where deadPids.contains(port.pid) {
                        HistoryManager.shared.addEntry(
                            port: port.port, processName: port.processName, action: .killed
                        )
                    }
                } else {
                    self.lastErrorMessage = "Kill failed"
                    self.showToast("Kill failed")
                }

                self.scheduleRefresh()
            }
        }
    }

    /// Kills all ports of a specific type
    func killAllPorts(ofType type: PortInfo.PortType) {
        killPorts(killablePorts(ofType: type))
    }
}
