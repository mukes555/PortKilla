import Foundation
import Combine

// MARK: - PortManager
class PortManager: ObservableObject {
    @Published var activePorts: [PortInfo] = []
    @Published var isRefreshing = false

    private let scanner = PortScanner()
    private let killer = ProcessKiller()
    private var refreshTimer: Timer?

    var refreshInterval: TimeInterval = 2.0 {
        didSet {
            restartTimer()
        }
    }

    init() {
        // Load initial preference
        refreshInterval = UserPreferences.shared.refreshInterval
        startAutoRefresh()

        // Listen for changes
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: .preferencesChanged, object: nil)
    }

    @objc private func preferencesChanged() {
        let newInterval = UserPreferences.shared.refreshInterval
        if abs(refreshInterval - newInterval) > 0.1 {
            refreshInterval = newInterval
        }
    }

    /// Starts automatic port refreshing
    func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval,
            repeats: true
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh() // Initial refresh
    }

    /// Stops automatic refreshing
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Restarts the refresh timer
    private func restartTimer() {
        stopAutoRefresh()
        startAutoRefresh()
    }

    /// Manually refreshes port list
    func refresh() {
        isRefreshing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let ports = self.scanner.scanActivePorts()

            DispatchQueue.main.async {
                self.checkWatchlist(newPorts: ports)
                self.activePorts = ports
                self.isRefreshing = false
            }
        }
    }

    /// Checks for watched ports and notifies if they appear
    private func checkWatchlist(newPorts: [PortInfo]) {
        let watched = WatchlistManager.shared.watchedPorts
        guard !watched.isEmpty else { return }

        let previousPorts = Set(activePorts.map { $0.port })

        for portInfo in newPorts {
            // If port is watched AND it wasn't active before
            if watched.contains(portInfo.port) && !previousPorts.contains(portInfo.port) {
                NotificationManager.shared.showSuccess(
                    "Watched port \(portInfo.port) is now active (\(portInfo.processName))"
                )
                // Log detected
                HistoryManager.shared.addEntry(
                    port: portInfo.port,
                    processName: portInfo.processName,
                    action: .detected
                )
            }
        }
    }

    /// Kills a specific port
    func killPort(_ portInfo: PortInfo, force: Bool = false) {
        // Run on background thread to prevent UI freeze
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.killer.killProcess(pid: portInfo.pid, force: force)

                // Verify death
                var isDead = false
                for _ in 0..<10 { // Wait up to 1 second
                    if !self.killer.isProcessRunning(portInfo.pid) {
                        isDead = true
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.1)
                }

                if isDead {
                    DispatchQueue.main.async {
                        // Optimistically remove from list for instant feedback
                        self.activePorts.removeAll { $0.id == portInfo.id }

                        // Log to history
                        HistoryManager.shared.addEntry(
                            port: portInfo.port,
                            processName: portInfo.processName,
                            action: .killed
                        )

                        NotificationManager.shared.showSuccess(
                            "Killed process on port \(portInfo.port)"
                        )

                        // Schedule a real refresh just to be safe/sync with system
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.refresh()
                        }
                    }
                } else {
                     throw ProcessKiller.KillError.unknownError("Process did not terminate.")
                }
            } catch {
                DispatchQueue.main.async {
                    NotificationManager.shared.showError(
                        "Failed to kill port \(portInfo.port): \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    /// Kills all ports of a specific type
    func killAllPorts(ofType type: PortInfo.PortType) {
        // Run on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let portsToKill = self.activePorts.filter { $0.type == type }
            let pids = portsToKill.map { $0.pid }

            let results = self.killer.killProcesses(pids: pids)

            // Verify death for successful kills
            var deadPids: [Int] = []

            for _ in 0..<10 { // Wait up to 1 second
                for pid in pids {
                    if !deadPids.contains(pid) && !self.killer.isProcessRunning(pid) {
                        deadPids.append(pid)
                    }
                }
                if deadPids.count == pids.count {
                    break
                }
                Thread.sleep(forTimeInterval: 0.1)
            }

            let successCount = deadPids.count

            DispatchQueue.main.async {
                if successCount > 0 {
                    // Remove verified dead ports instantly
                    self.activePorts.removeAll { port in
                        deadPids.contains(port.pid)
                    }

                    // Log bulk kill
                    for port in portsToKill {
                         if deadPids.contains(port.pid) {
                             HistoryManager.shared.addEntry(
                                port: port.port,
                                processName: port.processName,
                                action: .killed
                            )
                         }
                    }

                    NotificationManager.shared.showSuccess(
                        "Killed \(successCount) of \(pids.count) processes"
                    )
                } else if !pids.isEmpty {
                    NotificationManager.shared.showError("Failed to kill processes")
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.refresh()
                }
            }
        }
    }
}
