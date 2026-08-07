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

    let scanner = PortScanner()
    private let processScanner = ProcessScanner()
    let killer = ProcessKiller()
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
    var pendingFreeNotifications: Set<Int> = []

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

        // Demo-reel rendering drives state manually — no live scanning
        let isDemoMode = Foundation.ProcessInfo.processInfo.environment["PORTKILLA_DEMO_GIF"] != nil
        if !isDemoMode {
            startAutoRefresh()

            // Once a day, quietly see if a newer release exists
            if UpdateChecker.shouldAutoCheck() {
                checkForUpdates(manual: false)
            }
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

    func formatError(_ error: Error, context: String) -> String {
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

    func scheduleRefresh(after delay: TimeInterval = 2.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Kill actions

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
