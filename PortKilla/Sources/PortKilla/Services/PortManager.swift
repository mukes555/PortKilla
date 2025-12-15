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
                self.activePorts = ports
                self.isRefreshing = false
            }
        }
    }

    /// Kills a specific port
    func killPort(_ portInfo: PortInfo, force: Bool = false) {
        do {
            try killer.killProcess(pid: portInfo.pid, force: force)

            // Log to history
            HistoryManager.shared.addEntry(
                port: portInfo.port,
                processName: portInfo.processName,
                action: .killed
            )

            NotificationManager.shared.showSuccess(
                "Killed process on port \(portInfo.port)"
            )
            // Wait a bit and refresh
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.refresh()
            }
        } catch {
            NotificationManager.shared.showError(
                "Failed to kill port \(portInfo.port): \(error.localizedDescription)"
            )
        }
    }

    /// Kills all ports of a specific type
    func killAllPorts(ofType type: PortInfo.PortType) {
        let portsToKill = activePorts.filter { $0.type == type }
        let pids = portsToKill.map { $0.pid }

        let results = killer.killProcesses(pids: pids)
        let successCount = results.values.filter {
            if case .success = $0 { return true }
            return false
        }.count

        if successCount > 0 {
            // Log bulk kill
            for port in portsToKill {
                 HistoryManager.shared.addEntry(
                    port: port.port,
                    processName: port.processName,
                    action: .killed
                )
            }

            NotificationManager.shared.showSuccess(
                "Killed \(successCount) of \(pids.count) processes"
            )
        } else if !pids.isEmpty {
            NotificationManager.shared.showError("Failed to kill processes")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.refresh()
        }
    }
}
