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
        static let viewDensity = "PortKilla.viewDensity"
        static let showMenuBarCount = "PortKilla.showMenuBarCount"
        static let notificationsEnabled = "PortKilla.notificationsEnabled"
        static let watchedPorts = "PortKilla.watchedPorts"
        static let guardedPorts = "PortKilla.guardedPorts"
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

    /// Clean = one glanceable line per port; Advanced = command path, chips,
    /// CPU/age, tree expansion.
    enum ViewDensity: String { case clean, advanced }
    @Published var viewDensity: ViewDensity = .clean {
        didSet {
            UserDefaults.standard.set(viewDensity.rawValue, forKey: DefaultsKeys.viewDensity)
        }
    }

    /// Show the dev-port count next to the menu bar icon.
    @Published var showMenuBarCount: Bool = true {
        didSet {
            UserDefaults.standard.set(showMenuBarCount, forKey: DefaultsKeys.showMenuBarCount)
            onMenuBarPreferenceChanged?()
        }
    }

    /// Master switch for watch/guard notifications.
    @Published var notificationsEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: DefaultsKeys.notificationsEnabled)
            if notificationsEnabled { Notifier.requestPermission() }
        }
    }

    /// Set by the app delegate so a menu-bar preference change redraws it.
    var onMenuBarPreferenceChanged: (() -> Void)?

    /// Ports the user starred: a system notification fires when one frees up
    /// or when something new binds it.
    @Published var watchedPorts: Set<Int> = [] {
        didSet {
            UserDefaults.standard.set(Array(watchedPorts).sorted(), forKey: DefaultsKeys.watchedPorts)
        }
    }
    /// Guarded ports auto-kill any new (unprotected, user-owned) occupant.
    /// Strictly opt-in per port; a guarded port is always also watched.
    @Published var guardedPorts: Set<Int> = [] {
        didSet {
            UserDefaults.standard.set(Array(guardedPorts).sorted(), forKey: DefaultsKeys.guardedPorts)
        }
    }

    /// Occupancy of watched ports at the previous scan (port -> process name).
    private var watchedOccupancy: [Int: String] = [:]
    private var hasCompletedFirstScan = false

    /// One-shot "tell me when this frees up" armed when a kill didn't finish
    /// in time (slow shutdown, trapped SIGTERM).
    var pendingFreeNotifications: Set<Int> = []

    /// Recent guard kills per port; see `guardHasStruckOut`.
    private var guardStrikes: [Int: [Date]] = [:]

    /// Set when GitHub has a newer release; drives the "Download vX.Y.Z" menu item.
    @Published var updateAvailableVersion: String?

    init() {
        if let storedProtected = UserDefaults.standard.array(forKey: DefaultsKeys.protectedProcessSubstrings) as? [String] {
            protectedProcessSubstrings = Self.normalizeProtectedProcessSubstrings(storedProtected)
        } else {
            protectedProcessSubstrings = Self.normalizeProtectedProcessSubstrings(Self.defaultProtectedProcessSubstrings)
        }

        if let stored = UserDefaults.standard.object(forKey: DefaultsKeys.refreshIntervalSeconds) as? Double {
            refreshInterval = Self.sanitizedRefreshInterval(stored)
        }
        if let stored = UserDefaults.standard.object(forKey: DefaultsKeys.hideSystemProcesses) as? Bool {
            hideSystemProcesses = stored
        }
        if let stored = UserDefaults.standard.object(forKey: DefaultsKeys.confirmBeforeKill) as? Bool {
            confirmBeforeKill = stored
        }
        if let stored = UserDefaults.standard.string(forKey: DefaultsKeys.viewDensity),
           let density = ViewDensity(rawValue: stored) {
            viewDensity = density
        }
        if let stored = UserDefaults.standard.object(forKey: DefaultsKeys.showMenuBarCount) as? Bool {
            showMenuBarCount = stored
        }
        if let stored = UserDefaults.standard.object(forKey: DefaultsKeys.notificationsEnabled) as? Bool {
            notificationsEnabled = stored
        }
        if let stored = UserDefaults.standard.array(forKey: DefaultsKeys.watchedPorts) as? [Int] {
            watchedPorts = Set(stored.filter(Self.isValidPortNumber))
        }
        if let stored = UserDefaults.standard.array(forKey: DefaultsKeys.guardedPorts) as? [Int] {
            // A guard only makes sense on a watched port; the invariant is
            // enforced on writes, so re-establish it for whatever was stored.
            guardedPorts = Set(stored).intersection(watchedPorts)
        }
        shouldRestartTimerOnIntervalChange = true

        // In debug, the demo-GIF hook drives state manually — no live scanning.
        var isDemoMode = false
        #if DEBUG
        isDemoMode = Foundation.ProcessInfo.processInfo.environment["PORTKILLA_DEMO_GIF"] != nil
        #endif
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
        UpdateChecker.fetchNewerVersion { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .newer(let version):
                UpdateChecker.markChecked()
                self.updateAvailableVersion = version
                if manual { self.showToast("v\(version) available") }
            case .upToDate:
                UpdateChecker.markChecked()
                self.updateAvailableVersion = nil
                if manual { self.showToast("You're up to date") }
            case .failed(let reason):
                // Not marked as checked, so the next launch tries again.
                if manual { self.showToast("Couldn't check for updates: \(reason)") }
            }
        }
    }

    // MARK: - Watchlist

    func isWatched(_ port: Int) -> Bool {
        watchedPorts.contains(port)
    }

    func isGuarded(_ port: Int) -> Bool {
        guardedPorts.contains(port)
    }

    /// Confirmation happens in the UI — this just flips the state.
    func toggleGuard(_ port: Int) {
        if guardedPorts.contains(port) {
            guardedPorts.remove(port)
            showToast("Guard removed from :\(port)")
        } else {
            guardedPorts.insert(port)
            watchedPorts.insert(port) // guarding implies watching
            Notifier.requestPermission()
            showToast("Guarding :\(port)")
        }
    }

    func toggleWatch(_ port: Int) {
        if watchedPorts.contains(port) {
            watchedPorts.remove(port)
            guardedPorts.remove(port)
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
            } else if let now, was != now {
                // Newly occupied OR the occupant changed identity between scans
                // (a restart/swap must still fire the guard, not go unnoticed).
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
            // Watched ports already got a "free" notification from the watch
            // diff this cycle — don't send a second one for the same event.
            if !watchedPorts.contains(port) {
                notify(title: "Port \(port) is free", body: "The process finally exited — :\(port) is available now.")
            }
        }
        pendingFreeNotifications.subtract(freed)
    }

    /// Sends a notification only when the user has them enabled. Guard kills
    /// still happen regardless — only the alert is suppressed.
    private func notify(title: String, body: String) {
        guard notificationsEnabled else { return }
        Notifier.send(title: title, body: body)
    }

    /// A process that keeps coming back (pm2, nodemon, a launchd KeepAlive
    /// job) would otherwise be killed and announced on every scan, forever.
    /// After a few kills in quick succession the guard stands down instead.
    private static let guardStrikeLimit = 3
    private static let guardStrikeWindow: TimeInterval = 60

    func guardHasStruckOut(on port: Int) -> Bool {
        let now = Date()
        var recent = (guardStrikes[port] ?? []).filter { now.timeIntervalSince($0) < Self.guardStrikeWindow }
        recent.append(now)
        guardStrikes[port] = recent
        return recent.count > Self.guardStrikeLimit
    }

    /// A guard only ever fires against unprotected processes the user owns.
    private func guardKillTarget(for port: Int, in ports: [PortInfo]) -> PortInfo? {
        guard guardedPorts.contains(port),
              let occupant = ports.first(where: { $0.port == port }),
              !isProtectedProcessName(occupant.processName),
              !isSystemPort(occupant) else { return nil }
        return occupant
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
                    notify(title: "Port \(event.port) is free", body: "Nothing is listening on :\(event.port) anymore.")
                case .occupied(let name):
                    if let intruder = guardKillTarget(for: event.port, in: ports) {
                        if guardHasStruckOut(on: event.port) {
                            guardedPorts.remove(event.port)
                            guardStrikes[event.port] = nil
                            notify(
                                title: "Guard on :\(event.port) stood down",
                                body: "'\(intruder.processName)' keeps coming back. Stop it at the source, then re-enable the guard."
                            )
                        } else {
                            notify(
                                title: "Guard on :\(event.port)",
                                body: "Auto-killing '\(intruder.processName)' — it grabbed a guarded port."
                            )
                            killPort(intruder)
                        }
                    } else {
                        notify(title: "Port \(event.port) in use", body: "'\(name)' started listening on :\(event.port).")
                    }
                }
            }
        }
        watchedOccupancy = current
    }

    /// Identity of the list ignoring volatile per-scan metrics (CPU%, age).
    /// Two scans with the same signature render identically.
    static func stableSignature(_ ports: [PortInfo]) -> [String] {
        ports.map { port in
            let fields: [String] = [
                String(port.port),
                String(port.pid),
                port.proto,
                port.processName,
                String(port.memorySizeKB),
                port.type.rawValue,
                port.bindAddress ?? "",
                port.containerName ?? "",
                String(port.children?.count ?? 0)
            ]
            return fields.joined(separator: "|")
        }
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

    /// Restores every preference to its default and clears watch/guard state.
    func resetAllSettings() {
        refreshInterval = 2.0
        hideSystemProcesses = true
        confirmBeforeKill = true
        viewDensity = .clean
        showMenuBarCount = true
        notificationsEnabled = true
        protectedProcessSubstrings = Self.defaultProtectedProcessSubstrings
        watchedPorts = []
        guardedPorts = []
        showToast("Settings reset to defaults")
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
        let interval = Self.sanitizedRefreshInterval(refreshInterval)
        if interval <= 0 { return 0 } // manual only
        if isPopoverVisible { return interval }
        return max(interval, Self.backgroundRefreshInterval)
    }

    /// 0 means manual refresh; anything else is clamped to 1...300 seconds.
    /// Preferences are untrusted input: 0.01 would scan a hundred times a
    /// second, and NaN slips past a `<= 0` check and throws inside Timer.
    static func sanitizedRefreshInterval(_ value: Double) -> Double {
        guard value.isFinite else { return 2.0 }
        if value <= 0 { return 0 }
        return min(max(value, 1.0), 300)
    }

    static func isValidPortNumber(_ port: Int) -> Bool {
        (1...65535).contains(port)
    }

    deinit {
        stopAutoRefresh()
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
                    // Gate on a stable projection: cpuPercent/age change nearly
                    // every scan, so full-model `!=` would republish (and force a
                    // whole-list SwiftUI re-diff) every 2s even when nothing
                    // structural changed.
                    if Self.stableSignature(ports) != Self.stableSignature(self.activePorts) {
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
