import Foundation
import Combine

// MARK: - PortManager
class PortManager: ObservableObject {
    @Published var activePorts: [PortInfo] = []
    @Published var activeTests: [TestProcessInfo] = []
    @Published var isRefreshing = false
    @Published var lastUpdated: Date = Date()
    @Published var lastErrorMessage: String?
    @Published var toastMessage: String?

    private let scanner = PortScanner()
    private let processScanner = ProcessScanner()
    private let killer = ProcessKiller()
    private var refreshTimer: Timer?
    private var toastWorkItem: DispatchWorkItem?

    // Processes that should NEVER be killed by "Kill All" actions
    private let safeProcessNames = [
        "code helper", "cursor", "trae", "xcode", "antigravi", "google chrome", "slack", "electron",
        "intellij", "idea", "pycharm", "webstorm", "phpstorm", "goland", "rider", "rubymine", "datagrip", "appcode", "clion", "android studio",
        "sublime text", "atom", "nova", "bbedit", "coteditor", "textmate", "zed", "fleet", "windsurf"
    ]

    var refreshInterval: TimeInterval = 2.0 {
        didSet {
            restartTimer()
        }
    }

    init() {
        startAutoRefresh()
    }

    func killablePorts(ofType type: PortInfo.PortType) -> [PortInfo] {
        activePorts.filter { port in
            guard port.type == type else { return false }

            let processName = port.processName.lowercased()
            let isSafe = safeProcessNames.contains { safeName in
                processName.contains(safeName)
            }

            return !isSafe
        }
    }

    /// Starts automatic port refreshing
    func startAutoRefresh() {
        // 0 means manual refresh only
        if refreshInterval <= 0 {
            stopAutoRefresh()
            return
        }

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval,
            repeats: true
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh() // Initial refresh
    }

    // MARK: - Computed Properties
    var totalPortsMemory: String {
        let kb = activePorts.reduce(0) { $0 + $1.memorySizeKB }
        return formatMemory(kb)
    }

    var totalTestsMemory: String {
        let kb = activeTests.reduce(0) { $0 + $1.memorySizeKB }
        return formatMemory(kb)
    }

    private func formatMemory(_ kb: Int) -> String {
        let mb = Double(kb) / 1024.0
        if mb < 1 { return "\(kb) KB" }
        else if mb < 1024 { return String(format: "%.1f MB", mb) }
        else { return String(format: "%.2f GB", mb / 1024.0) }
    }

    // MARK: - Actions
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
    func refresh(showToast: Bool = false) {
        if isRefreshing {
            return
        }
        isRefreshing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let tests = self.processScanner.scanTestProcesses()
            let portsResult = Result { try self.scanner.scanActivePorts() }

            DispatchQueue.main.async {
                self.activeTests = tests
                self.isRefreshing = false

                switch portsResult {
                case .success(let ports):
                    self.activePorts = ports
                    self.lastUpdated = Date()
                    self.lastErrorMessage = nil
                    if showToast {
                        self.showToast("Refreshed")
                    }
                case .failure(let error):
                    self.lastErrorMessage = self.formatError(error, context: "Refresh failed")
                    if showToast {
                        self.showToast(self.lastErrorMessage ?? "Refresh failed")
                    }
                }
            }
        }
    }

    private func showToast(_ message: String) {
        toastWorkItem?.cancel()
        toastMessage = message

        let workItem = DispatchWorkItem { [weak self] in
            self?.toastMessage = nil
        }
        toastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func formatError(_ error: Error, context: String) -> String {
        if let scanError = error as? PortScanner.ScanError {
            switch scanError {
            case .invalidOutput:
                return "\(context): invalid command output"
            case .commandFailed(let code):
                return "\(context): lsof failed (exit \(code))"
            }
        }
        return "\(context): \(error.localizedDescription)"
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
                        self.lastErrorMessage = nil
                        self.showToast("Killed :\(portInfo.port)")

                        // Log to history
                        HistoryManager.shared.addEntry(
                            port: portInfo.port,
                            processName: portInfo.processName,
                            action: .killed
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
                    self.lastErrorMessage = self.formatError(error, context: "Kill failed for :\(portInfo.port)")
                    self.showToast(self.lastErrorMessage ?? "Kill failed")
                }
            }
        }
    }

    /// Kills a specific test process
    func killTestProcess(_ testInfo: TestProcessInfo, force: Bool = false) {
        // Run on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.killer.killProcess(pid: testInfo.pid, force: force)

                // Verify death
                var isDead = false
                for _ in 0..<10 {
                    if !self.killer.isProcessRunning(testInfo.pid) {
                        isDead = true
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.1)
                }

                if isDead {
                    DispatchQueue.main.async {
                        self.activeTests.removeAll { $0.id == testInfo.id }
                        self.lastErrorMessage = nil
                        self.showToast("Killed \(testInfo.processName)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastErrorMessage = self.formatError(error, context: "Kill failed for \(testInfo.processName)")
                    self.showToast(self.lastErrorMessage ?? "Kill failed")
                }
            }
        }
    }

    /// Kills all ports of a specific type
    func killAllPorts(ofType type: PortInfo.PortType) {
        let portsToKill = killablePorts(ofType: type)

        // Run on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

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
            let failureCount = results.values.filter {
                if case .failure = $0 { return true }
                return false
            }.count

            DispatchQueue.main.async {
                if successCount > 0 {
                    // Remove verified dead ports instantly
                    self.activePorts.removeAll { port in
                        deadPids.contains(port.pid)
                    }
                    self.lastErrorMessage = nil
                    if failureCount > 0 {
                        self.showToast("Killed \(successCount), \(failureCount) failed")
                    } else {
                        self.showToast("Killed \(successCount) process\(successCount == 1 ? "" : "es")")
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
                } else if !pids.isEmpty {
                    self.lastErrorMessage = "Kill all failed"
                    self.showToast("Kill all failed")
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.refresh()
                }
            }
        }
    }
}
