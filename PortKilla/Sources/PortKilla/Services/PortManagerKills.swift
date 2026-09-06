import Foundation

/// Who asked for a kill; recorded in history so an agent whose server
/// vanished can find out what happened to it.
enum KillInitiator: String {
    case user = "you"
    case portGuard = "port guard"
    case link = "link"
}

// MARK: - Kill flows
// Every product-facing kill runs the same pipeline: signal on a background
// queue (identity-checked), wait for the exit event, then report on main.
extension PortManager {

    /// Event-driven wait for process exits (DispatchSourceProcess) instead of
    /// polling sleeps, with a final liveness sweep to catch processes that
    /// died before the kernel source was armed. Call from a background queue.
    /// SIGTERM gives a process time to unwind (Node, Java, Postgres routinely
    /// take a few seconds); SIGKILL is immediate, so a short wait suffices.
    static func exitTimeout(force: Bool) -> TimeInterval {
        force ? 1.0 : 3.0
    }

    func waitForExit(pids: [Int], timeout: TimeInterval) -> Set<Int> {
        let condition = NSCondition()
        var dead = Set<Int>()
        // Set under the lock once waiting is over; a handler the kernel had
        // already queued then sees it and leaves `dead` alone, so the result
        // is fixed the moment this function decides it.
        var finished = false
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
                if !finished {
                    dead.insert(pid)
                    condition.signal()
                }
                condition.unlock()
            }
            source.activate()
            sources.append(source)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while dead.count < pids.count {
            if !condition.wait(until: deadline) { break }
        }

        // Sweep for exits that raced the source activation, still under the
        // lock so no handler interleaves, then freeze the result.
        for pid in pids where !dead.contains(pid) && !killer.isProcessRunning(pid) {
            dead.insert(pid)
        }
        finished = true
        let result = dead
        condition.unlock()

        sources.forEach { $0.cancel() }
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
        terminatingPids.insert(pid)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.killer.killProcess(pid: pid, force: force, killTree: killTree, expectedName: expectedName)
                let timeout = Self.exitTimeout(force: force)
                let died = self.waitForExit(pids: [pid], timeout: timeout).contains(pid)

                Log.kill.info("\(subject, privacy: .public) pid \(pid) force=\(force) tree=\(killTree) exited=\(died)")
                DispatchQueue.main.async {
                    self.terminatingPids.remove(pid)
                    if died {
                        self.lastErrorMessage = nil
                        onKilled()
                    } else {
                        // Not a failure yet: the signal was delivered and the
                        // process may still be shutting down.
                        let hint = force ? "" : " Option+click to force kill (SIGKILL)."
                        self.lastErrorMessage = "\(subject) is still shutting down.\(hint)"
                        onNotTerminated?()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.terminatingPids.remove(pid)
                    self.lastErrorMessage = self.formatError(error, context: errorContext)
                    self.showToast(self.lastErrorMessage ?? "Kill failed")
                }
            }
        }
    }

    func killPort(_ portInfo: PortInfo, force: Bool = false, killTree: Bool = false, initiator: KillInitiator = .user) {
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
                self.history.addEntry(
                    port: portInfo.port, processName: portInfo.processName, action: .killed,
                    owner: portInfo.agentOwner?.name, killedBy: initiator.rawValue
                )
                self.scheduleRefresh()
            },
            onNotTerminated: { [weak self] in
                self?.showToast(":\(portInfo.port) still shutting down, will notify when free")
                self?.pendingFreeNotifications.insert(portInfo.port)
            }
        )
    }

    /// Kills whatever listens on a port number (used by the URL scheme).
    /// Scans fresh so it works even when the cached list is stale.
    /// `respectProtected` refuses to kill a protected process — always true for
    /// link-initiated kills so a webpage can't terminate the user's IDE/tools.
    ///
    /// `confirm` runs on the main thread with the target found by the fresh
    /// scan, so a link-initiated kill can show who owns the port before
    /// asking; returning false cancels.
    func killPortNumber(_ portNumber: Int, force: Bool = false, respectProtected: Bool = false,
                        initiator: KillInitiator = .user, confirm: ((PortInfo) -> Bool)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let table = ProcessTable.capture()
            let ports = (try? self.scanner.scanActivePorts(processes: table)) ?? []

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
            DispatchQueue.main.async {
                if let confirm, !confirm(target) { return }
                self.killPort(target, force: force, initiator: initiator)
            }
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

            let dead = self.waitForExit(pids: tests.map { $0.pid }, timeout: Self.exitTimeout(force: force))

            DispatchQueue.main.async {
                self.activeTests.removeAll { dead.contains($0.pid) }
                let stillRunning = tests.count - dead.count
                if stillRunning > 0 {
                    self.showToast("Killed \(dead.count), \(stillRunning) still shutting down")
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
        terminatingPids.formUnion(targets.map(\.pid))

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            for target in targets {
                try? self.killer.killProcess(pid: target.pid, force: force, expectedName: target.processName)
            }

            let deadPids = self.waitForExit(pids: targets.map { $0.pid }, timeout: Self.exitTimeout(force: force))
            let successCount = deadPids.count

            DispatchQueue.main.async {
                self.terminatingPids.subtract(targets.map(\.pid))
                if successCount > 0 {
                    self.activePorts.removeAll { deadPids.contains($0.pid) }
                    self.lastErrorMessage = nil

                    let stillRunning = targets.count - successCount
                    if stillRunning > 0 {
                        self.showToast("Killed \(successCount), \(stillRunning) still shutting down")
                    } else {
                        self.showToast("Killed \(successCount) process\(successCount == 1 ? "" : "es")")
                    }

                    for port in ports where deadPids.contains(port.pid) {
                        self.history.addEntry(
                            port: port.port, processName: port.processName, action: .killed,
                            owner: port.agentOwner?.name, killedBy: KillInitiator.user.rawValue
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


    // MARK: - Docker

    /// Stops a Docker container by name
    func stopDockerContainer(_ name: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try DockerService.shared.stopContainer(name: name)

                DispatchQueue.main.async {
                    self.showToast("Stopped container \(name)")
                    self.lastErrorMessage = nil
                    self.scheduleRefresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastErrorMessage = self.formatError(error, context: "Failed to stop container")
                    self.showToast("Stop failed")
                }
            }
        }
    }
}
