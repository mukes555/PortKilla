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
    private var shouldRestartTimerOnIntervalChange = false

    /// While the popover is closed only the menu-bar count consumes the data,
    /// so the scan slows down to save CPU and battery.
    private static let backgroundRefreshInterval: TimeInterval = 30.0
    private var isPopoverVisible = false

    private enum DefaultsKeys {
        static let refreshIntervalSeconds = "PortKilla.refreshIntervalSeconds"
        static let protectedProcessSubstrings = "PortKilla.protectedProcessSubstrings"
        static let hideSystemProcesses = "PortKilla.hideSystemProcesses"
        static let confirmBeforeKill = "PortKilla.confirmBeforeKill"
        static let watchedPorts = "PortKilla.watchedPorts"
    }

    private static let defaultProtectedProcessSubstrings = [
        "code helper", "cursor", "trae", "xcode", "antigravi", "google chrome", "slack", "electron",
        "intellij", "idea", "pycharm", "webstorm", "phpstorm", "goland", "rider", "rubymine", "datagrip", "appcode", "clion", "android studio",
        "sublime text", "atom", "nova", "bbedit", "coteditor", "textmate", "zed", "fleet", "windsurf"
    ]

    @Published var protectedProcessSubstrings: [String] = [] {
        didSet {
            let normalized = Self.normalizeProtectedProcessSubstrings(protectedProcessSubstrings)
            if normalized != protectedProcessSubstrings {
                protectedProcessSubstrings = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: DefaultsKeys.protectedProcessSubstrings)
        }
    }

    @Published var refreshInterval: TimeInterval = 2.0 {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: DefaultsKeys.refreshIntervalSeconds)
            if shouldRestartTimerOnIntervalChange {
                restartTimer()
            }
        }
    }

    /// Default on: system daemons (rapportd, AirPlay, …) drown out the handful
    /// of dev servers the user actually cares about.
    @Published var hideSystemProcesses: Bool = true {
        didSet {
            UserDefaults.standard.set(hideSystemProcesses, forKey: DefaultsKeys.hideSystemProcesses)
        }
    }

    @Published var confirmBeforeKill: Bool = true {
        didSet {
            UserDefaults.standard.set(confirmBeforeKill, forKey: DefaultsKeys.confirmBeforeKill)
        }
    }

    /// Ports the user starred: a system notification fires when one frees up
    /// or when something new binds it.
    @Published var watchedPorts: Set<Int> = [] {
        didSet {
            UserDefaults.standard.set(Array(watchedPorts).sorted(), forKey: DefaultsKeys.watchedPorts)
        }
    }
    /// Occupancy of watched ports at the previous scan (port -> process name).
    private var watchedOccupancy: [Int: String] = [:]
    private var hasCompletedFirstScan = false

    /// One-shot "tell me when this frees up" armed when a kill didn't finish
    /// in time (slow shutdown, trapped SIGTERM).
    private var pendingFreeNotifications: Set<Int> = []

    /// Set when GitHub has a newer release; drives the "Download vX.Y.Z" menu item.
    @Published var updateAvailableVersion: String?

    init() {
        if let storedProtected = UserDefaults.standard.array(forKey: DefaultsKeys.protectedProcessSubstrings) as? [String] {
            protectedProcessSubstrings = Self.normalizeProtectedProcessSubstrings(storedProtected)
        } else {
            protectedProcessSubstrings = Self.normalizeProtectedProcessSubstrings(Self.defaultProtectedProcessSubstrings)
        }

        if let stored = UserDefaults.standard.object(forKey: DefaultsKeys.refreshIntervalSeconds) as? Double {
            refreshInterval = stored
        }
        if let stored = UserDefaults.standard.object(forKey: DefaultsKeys.hideSystemProcesses) as? Bool {
            hideSystemProcesses = stored
        }
        if let stored = UserDefaults.standard.object(forKey: DefaultsKeys.confirmBeforeKill) as? Bool {
            confirmBeforeKill = stored
        }
        if let stored = UserDefaults.standard.array(forKey: DefaultsKeys.watchedPorts) as? [Int] {
            watchedPorts = Set(stored)
        }
        shouldRestartTimerOnIntervalChange = true
        startAutoRefresh()

        // Once a day, quietly see if a newer release exists
        if UpdateChecker.shouldAutoCheck() {
            checkForUpdates(manual: false)
        }
    }

    // MARK: - Updates

    func checkForUpdates(manual: Bool) {
        UpdateChecker.markChecked()
        UpdateChecker.fetchNewerVersion { [weak self] newer in
            guard let self = self else { return }
            self.updateAvailableVersion = newer
            if manual {
                self.showToast(newer.map { "v\($0) available" } ?? "You're up to date")
            }
        }
    }

    // MARK: - Watchlist

    func isWatched(_ port: Int) -> Bool {
        watchedPorts.contains(port)
    }

    func toggleWatch(_ port: Int) {
        if watchedPorts.contains(port) {
            watchedPorts.remove(port)
            watchedOccupancy.removeValue(forKey: port)
            showToast("Stopped watching :\(port)")
        } else {
            watchedPorts.insert(port)
            // Seed current occupancy so adding a busy port doesn't notify immediately
            watchedOccupancy[port] = activePorts.first { $0.port == port }?.processName
            Notifier.requestPermission()
            showToast("Watching :\(port)")
        }
    }

    struct WatchEvent: Equatable {
        enum Kind: Equatable { case freed, occupied(by: String) }
        let port: Int
        let kind: Kind
    }

    /// Diffs watched-port occupancy between two scans.
    static func watchEvents(
        watched: Set<Int>,
        previous: [Int: String],
        current: [Int: String]
    ) -> [WatchEvent] {
        var events: [WatchEvent] = []
        for port in watched.sorted() {
            let was = previous[port]
            let now = current[port]
            if was != nil && now == nil {
                events.append(WatchEvent(port: port, kind: .freed))
            } else if was == nil, let now {
                events.append(WatchEvent(port: port, kind: .occupied(by: now)))
            }
        }
        return events
    }

    private func firePendingFreeNotifications(with ports: [PortInfo]) {
        guard !pendingFreeNotifications.isEmpty else { return }

        let stillBusy = Set(ports.map { $0.port })
        let freed = pendingFreeNotifications.subtracting(stillBusy)
        for port in freed.sorted() {
            Notifier.send(title: "Port \(port) is free", body: "The process finally exited — :\(port) is available now.")
        }
        pendingFreeNotifications.subtract(freed)
    }

    private func processWatchedPorts(with ports: [PortInfo]) {
        guard !watchedPorts.isEmpty else {
            watchedOccupancy = [:]
            return
        }

        var current: [Int: String] = [:]
        for port in watchedPorts {
            current[port] = ports.first { $0.port == port }?.processName
        }

        // The very first scan just establishes the baseline
        if hasCompletedFirstScan {
            for event in Self.watchEvents(watched: watchedPorts, previous: watchedOccupancy, current: current) {
                switch event.kind {
                case .freed:
                    Notifier.send(title: "Port \(event.port) is free", body: "Nothing is listening on :\(event.port) anymore.")
                case .occupied(let name):
                    Notifier.send(title: "Port \(event.port) in use", body: "'\(name)' started listening on :\(event.port).")
                }
            }
        }
        watchedOccupancy = current
    }

    // MARK: - System process detection

    private static let systemPathPrefixes = [
        "/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"
    ]

    /// True for ports owned by other users (root, _daemons) or by binaries
    /// living in system locations.
    func isSystemPort(_ port: PortInfo) -> Bool {
        if port.user != NSUserName() {
            return true
        }
        return Self.systemPathPrefixes.contains { port.command.hasPrefix($0) }
    }

    /// The ports the list actually shows, honoring the hide-system setting.
    var visiblePorts: [PortInfo] {
        hideSystemProcesses ? activePorts.filter { !isSystemPort($0) } : activePorts
    }

    /// Menu-bar badge: only dev-relevant ports. Counting every system daemon
    /// made the badge permanently ~30 and therefore meaningless.
    var menuBarBadgeCount: Int {
        activePorts.filter { !isSystemPort($0) && $0.type != .ide }.count
    }

    /// How many ports the hide-system filter is currently swallowing.
    var hiddenSystemPortsCount: Int {
        hideSystemProcesses ? activePorts.count - visiblePorts.count : 0
    }

    func killablePorts(ofType type: PortInfo.PortType) -> [PortInfo] {
        activePorts.filter { port in
            guard port.type == type else { return false }
            return !isProtectedProcessName(port.processName)
        }
    }

    func isProtectedProcessName(_ processName: String) -> Bool {
        let lower = processName.lowercased()
        return protectedProcessSubstrings.contains { lower.contains($0) }
    }

    func resetProtectedProcessSubstrings() {
        protectedProcessSubstrings = Self.defaultProtectedProcessSubstrings
    }

    private static func normalizeProtectedProcessSubstrings(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.isEmpty { continue }
            if result.contains(normalized) { continue }
            result.append(normalized)
        }
        return result
    }

    // MARK: - Refresh scheduling

    /// Called by the app delegate when the popover opens/closes so the timer
    /// can switch between the foreground and background cadence.
    func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        restartTimer()

        let isManualMode = refreshInterval <= 0
        if visible && isManualMode {
            refresh()
        }
    }

    private var effectiveRefreshInterval: TimeInterval {
        if refreshInterval <= 0 { return 0 } // manual only
        if isPopoverVisible { return refreshInterval }
        return max(refreshInterval, Self.backgroundRefreshInterval)
    }

    /// Starts automatic port refreshing
    func startAutoRefresh() {
        stopAutoRefresh()

        let interval = effectiveRefreshInterval
        if interval <= 0 {
            return
        }

        let timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.refresh()
        }
        // Let macOS coalesce wakeups for power efficiency.
        timer.tolerance = interval * 0.1
        refreshTimer = timer

        refresh() // Initial refresh
    }

    /// Stops automatic refreshing
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func restartTimer() {
        stopAutoRefresh()
        startAutoRefresh()
    }

    // MARK: - Computed Properties
    var totalPortsMemory: String {
        MemoryFormat.string(kilobytes: activePorts.reduce(0) { $0 + $1.memorySizeKB })
    }

    var totalTestsMemory: String {
        MemoryFormat.string(kilobytes: activeTests.reduce(0) { $0 + $1.memorySizeKB })
    }

    // MARK: - Refresh

    /// Manually refreshes port list
    func refresh(showToast: Bool = false) {
        if isRefreshing {
            return
        }
        isRefreshing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // One ps snapshot shared by both scanners (was one ps/pgrep per port).
            let processTable = ProcessTable.capture()
            let tests = self.processScanner.scanTestProcesses(processes: processTable)
            let portsResult = Result { try self.scanner.scanActivePorts(processes: processTable) }

            DispatchQueue.main.async {
                if tests != self.activeTests {
                    self.activeTests = tests
                }
                self.isRefreshing = false

                switch portsResult {
                case .success(let ports):
                    if ports != self.activePorts {
                        self.activePorts = ports
                    }
                    self.processWatchedPorts(with: ports)
                    self.firePendingFreeNotifications(with: ports)
                    self.hasCompletedFirstScan = true
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

    func showToast(_ message: String) {
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

    /// Polls until the given PIDs exit or the timeout passes; returns the dead ones.
    private func waitForExit(pids: [Int], timeout: TimeInterval = 1.0) -> Set<Int> {
        var dead = Set<Int>()
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            for pid in pids where !dead.contains(pid) {
                if !killer.isProcessRunning(pid) {
                    dead.insert(pid)
                }
            }
            if dead.count == pids.count || Date() >= deadline {
                return dead
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func scheduleRefresh(after delay: TimeInterval = 2.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Kill actions

    /// Kills a specific port
    func killPort(_ portInfo: PortInfo, force: Bool = false, killTree: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.killer.killProcess(
                    pid: portInfo.pid,
                    force: force,
                    killTree: killTree,
                    expectedName: portInfo.processName
                )

                let died = self.waitForExit(pids: [portInfo.pid]).contains(portInfo.pid)

                DispatchQueue.main.async {
                    if died {
                        // Optimistically remove from list for instant feedback
                        self.activePorts.removeAll { $0.id == portInfo.id }
                        self.lastErrorMessage = nil
                        let action = killTree ? "Killed Tree" : "Killed"
                        self.showToast("\(action) :\(portInfo.port)")

                        HistoryManager.shared.addEntry(
                            port: portInfo.port,
                            processName: portInfo.processName,
                            action: .killed
                        )

                        // Sync with the system shortly after
                        self.scheduleRefresh()
                    } else {
                        let hint = force ? "" : " Option+click the kill button to force kill (SIGKILL)."
                        self.lastErrorMessage = ":\(portInfo.port) did not terminate.\(hint)"
                        self.showToast("Kill failed for :\(portInfo.port)")
                        // Slow shutdowns are common — tell the user when it's done
                        self.pendingFreeNotifications.insert(portInfo.port)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastErrorMessage = self.formatError(error, context: "Kill failed for :\(portInfo.port)")
                    self.showToast(self.lastErrorMessage ?? "Kill failed")
                }
            }
        }
    }

    /// Kills whatever listens on a port number (used by the URL scheme).
    /// Scans fresh so it works even when the cached list is stale.
    func killPortNumber(_ portNumber: Int, force: Bool = false) {
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
            self.killPort(target, force: force)
        }
    }

    /// Kills an arbitrary process (used for children in the process tree).
    func killProcess(pid: Int, name: String, force: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.killer.killProcess(pid: pid, force: force, expectedName: name)
                let died = self.waitForExit(pids: [pid]).contains(pid)

                DispatchQueue.main.async {
                    if died {
                        self.lastErrorMessage = nil
                        self.showToast("Killed \(name)")
                        self.scheduleRefresh(after: 0.5)
                    } else {
                        let hint = force ? "" : " Option+click to force kill (SIGKILL)."
                        self.lastErrorMessage = "\(name) did not terminate.\(hint)"
                        self.showToast("Kill failed")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastErrorMessage = self.formatError(error, context: "Kill failed for \(name)")
                    self.showToast(self.lastErrorMessage ?? "Kill failed")
                }
            }
        }
    }

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

    /// Kills a specific test process
    func killTestProcess(_ testInfo: TestProcessInfo, force: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.killer.killProcess(
                    pid: testInfo.pid,
                    force: force,
                    expectedName: testInfo.processName
                )

                let died = self.waitForExit(pids: [testInfo.pid]).contains(testInfo.pid)

                DispatchQueue.main.async {
                    if died {
                        self.activeTests.removeAll { $0.id == testInfo.id }
                        self.lastErrorMessage = nil
                        self.showToast("Killed \(testInfo.processName)")
                    } else {
                        let hint = force ? "" : " Option+click to force kill (SIGKILL)."
                        self.lastErrorMessage = "\(testInfo.processName) did not terminate.\(hint)"
                        self.showToast("Kill failed")
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

    /// Kills several test processes in one pass (one background block, one
    /// verification wait — killing N tests no longer parks N sleeping threads).
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

            var killErrors = 0
            for target in targets {
                do {
                    try self.killer.killProcess(pid: target.pid, force: force, expectedName: target.processName)
                } catch {
                    killErrors += 1
                }
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
                            port: port.port,
                            processName: port.processName,
                            action: .killed
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
