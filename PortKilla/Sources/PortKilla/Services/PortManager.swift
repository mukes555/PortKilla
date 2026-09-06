import Foundation
import Combine

/// "Updated 2s ago" ticks on its own object so the footer alone re-renders
/// when a scan lands; publishing it from PortManager re-evaluated every row.
final class RefreshClock: ObservableObject {
    @Published var lastUpdated = Date()
}

// MARK: - PortManager
class PortManager: ObservableObject {
    @Published var activePorts: [PortInfo] = [] {
        didSet {
            activeSignature = Self.stableSignature(activePorts)
            recomputeVisiblePorts()
            onPortsChanged?()
        }
    }
    @Published var activeTests: [TestProcessInfo] = []
    @Published var lastErrorMessage: String?
    @Published var toastMessage: String?
    let clock = RefreshClock()

    /// Published once, so the list can show "scanning" instead of a
    /// premature "no ports" before any data exists.
    @Published var hasCompletedFirstScan = false
    /// The slow lsof path is in use (libproc unavailable); shown in the footer.
    @Published var isCompatibilityScan = false
    /// Processes a kill has been sent to and that have not exited yet; rows
    /// dim while they shut down.
    @Published var terminatingPids: Set<Int> = []
    var lastUpdated: Date { clock.lastUpdated }

    /// Not published: no view reads it, and publishing it forced two
    /// whole-tree re-renders per refresh even when nothing changed.
    var isRefreshing = false
    /// Full-depth signature of `activePorts`, kept so a refresh compares one
    /// side instead of rebuilding both.
    var activeSignature: [String] = []
    var lastTestsPublish = Date.distantPast

    /// The ports the list shows, honoring the hide-system setting. Cached:
    /// it was recomputed on every access, thousands of times a minute.
    private(set) var visiblePorts: [PortInfo] = []
    /// Menu-bar badge: only dev-relevant ports. Counting every system daemon
    /// made the badge permanently ~30 and therefore meaningless.
    private(set) var menuBarBadgeCount = 0
    /// Set by the app delegate; fires after `activePorts` has changed.
    var onPortsChanged: (() -> Void)?

    /// Preferences restored in init must not write themselves back or
    /// trigger side effects (a notification-permission prompt on launch).
    private var isRestoringPreferences = true

    let scanner = PortScanner()
    let processScanner = ProcessScanner()
    let killer = ProcessKiller()
    var refreshTimer: Timer?
    private var toastWorkItem: DispatchWorkItem?
    var shouldRestartTimerOnIntervalChange = false

    /// While the popover is closed only the menu-bar count consumes the data,
    /// so the scan slows down to save CPU and battery.
    static let backgroundRefreshInterval: TimeInterval = 30.0
    var isUIVisible = false


    static let defaultProtectedProcessSubstrings = KnownEditors.substrings

    @Published var protectedProcessSubstrings: [String] = [] {
        didSet {
            let normalized = Self.normalizeProtectedProcessSubstrings(protectedProcessSubstrings)
            if normalized != protectedProcessSubstrings {
                protectedProcessSubstrings = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: DefaultsKey.protectedProcessSubstrings)
        }
    }

    @Published var refreshInterval: TimeInterval = 2.0 {
        didSet {
            guard !isRestoringPreferences else { return }
            UserDefaults.standard.set(refreshInterval, forKey: DefaultsKey.refreshIntervalSeconds)
            if shouldRestartTimerOnIntervalChange {
                restartTimer()
            }
        }
    }

    /// Default on: system daemons (rapportd, AirPlay, …) drown out the handful
    /// of dev servers the user actually cares about.
    @Published var hideSystemProcesses: Bool = true {
        didSet {
            recomputeVisiblePorts()
            guard !isRestoringPreferences else { return }
            UserDefaults.standard.set(hideSystemProcesses, forKey: DefaultsKey.hideSystemProcesses)
        }
    }

    @Published var confirmBeforeKill: Bool = true {
        didSet {
            guard !isRestoringPreferences else { return }
            UserDefaults.standard.set(confirmBeforeKill, forKey: DefaultsKey.confirmBeforeKill)
        }
    }

    /// Clean = one glanceable line per port; Advanced = command path, chips,
    /// CPU/age, tree expansion.
    /// Raw values are what older versions stored; the case names match the UI.
    enum ViewDensity: String {
        case simple = "clean"
        case advanced
    }
    @Published var viewDensity: ViewDensity = .simple {
        didSet {
            guard !isRestoringPreferences else { return }
            UserDefaults.standard.set(viewDensity.rawValue, forKey: DefaultsKey.viewDensity)
        }
    }

    /// Show the dev-port count next to the menu bar icon.
    @Published var showMenuBarCount: Bool = true {
        didSet {
            guard !isRestoringPreferences else { return }
            UserDefaults.standard.set(showMenuBarCount, forKey: DefaultsKey.showMenuBarCount)
            onMenuBarPreferenceChanged?()
        }
    }

    /// Master switch for watch/guard notifications. Permission is requested
    /// when the user turns it on or arms a watch, never just for launching.
    @Published var notificationsEnabled: Bool = true {
        didSet {
            guard !isRestoringPreferences else { return }
            UserDefaults.standard.set(notificationsEnabled, forKey: DefaultsKey.notificationsEnabled)
            if notificationsEnabled { Notifier.requestPermission() }
        }
    }

    @Published var notificationSound: Bool = true {
        didSet {
            guard !isRestoringPreferences else { return }
            UserDefaults.standard.set(notificationSound, forKey: DefaultsKey.notificationSound)
        }
    }

    /// How many kills the History window keeps.
    @Published var historyLimit: Int = 50 {
        didSet {
            HistoryManager.shared.maxHistoryItems = historyLimit
            guard !isRestoringPreferences else { return }
            UserDefaults.standard.set(historyLimit, forKey: DefaultsKey.historyLimit)
        }
    }

    /// Set by the app delegate so a menu-bar preference change redraws it.
    var onMenuBarPreferenceChanged: (() -> Void)?

    /// Ports the user starred: a system notification fires when one frees up
    /// or when something new binds it.
    @Published var watchedPorts: Set<Int> = [] {
        didSet {
            guard !isRestoringPreferences else { return }
            UserDefaults.standard.set(Array(watchedPorts).sorted(), forKey: DefaultsKey.watchedPorts)
        }
    }
    /// Guarded ports auto-kill any new (unprotected, user-owned) occupant.
    /// Strictly opt-in per port; a guarded port is always also watched.
    @Published var guardedPorts: Set<Int> = [] {
        didSet {
            guard !isRestoringPreferences else { return }
            UserDefaults.standard.set(Array(guardedPorts).sorted(), forKey: DefaultsKey.guardedPorts)
        }
    }

    /// Occupancy of watched ports at the previous scan (port -> process name).
    var watchedOccupancy: [Int: String] = [:]

    /// One-shot "tell me when this frees up" armed when a kill didn't finish
    /// in time (slow shutdown, trapped SIGTERM).
    var pendingFreeNotifications: Set<Int> = []

    /// Recent guard kills per port; see `guardHasStruckOut`.
    var guardStrikes: [Int: [Date]] = [:]

    /// Set when GitHub has a newer release; drives the "Download vX.Y.Z" menu item.
    @Published var updateAvailableVersion: String?

    init() {
        if let storedProtected = UserDefaults.standard.array(forKey: DefaultsKey.protectedProcessSubstrings) as? [String] {
            protectedProcessSubstrings = Self.normalizeProtectedProcessSubstrings(storedProtected)
        } else {
            protectedProcessSubstrings = Self.normalizeProtectedProcessSubstrings(Self.defaultProtectedProcessSubstrings)
        }

        if let stored = UserDefaults.standard.object(forKey: DefaultsKey.refreshIntervalSeconds) as? Double {
            refreshInterval = Self.sanitizedRefreshInterval(stored)
        }
        if let stored = UserDefaults.standard.object(forKey: DefaultsKey.hideSystemProcesses) as? Bool {
            hideSystemProcesses = stored
        }
        if let stored = UserDefaults.standard.object(forKey: DefaultsKey.confirmBeforeKill) as? Bool {
            confirmBeforeKill = stored
        }
        if let stored = UserDefaults.standard.string(forKey: DefaultsKey.viewDensity),
           let density = ViewDensity(rawValue: stored) {
            viewDensity = density
        }
        if let stored = UserDefaults.standard.object(forKey: DefaultsKey.showMenuBarCount) as? Bool {
            showMenuBarCount = stored
        }
        if let stored = UserDefaults.standard.object(forKey: DefaultsKey.notificationsEnabled) as? Bool {
            notificationsEnabled = stored
        }
        if let stored = UserDefaults.standard.array(forKey: DefaultsKey.watchedPorts) as? [Int] {
            watchedPorts = Set(stored.filter(Self.isValidPortNumber))
        }
        if let stored = UserDefaults.standard.object(forKey: DefaultsKey.notificationSound) as? Bool {
            notificationSound = stored
        }
        if let stored = UserDefaults.standard.object(forKey: DefaultsKey.historyLimit) as? Int, (10...1000).contains(stored) {
            historyLimit = stored
        }
        if let stored = UserDefaults.standard.array(forKey: DefaultsKey.guardedPorts) as? [Int] {
            // A guard only makes sense on a watched port; the invariant is
            // enforced on writes, so re-establish it for whatever was stored.
            guardedPorts = Set(stored).intersection(watchedPorts)
        }
        shouldRestartTimerOnIntervalChange = true
        isRestoringPreferences = false

        // In debug, the demo-GIF hook drives state manually — no live scanning.
        var isDemoMode = false
        #if DEBUG
        isDemoMode = Foundation.ProcessInfo.processInfo.environment["PORTKILLA_DEMO_GIF"] != nil
        #endif
        if !isDemoMode {
            startAutoRefresh()

            // Once a day, quietly see if a newer release exists. Deferred so
            // launch never waits on the network.
            if UpdateChecker.shouldAutoCheck() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    self?.checkForUpdates(manual: false)
                }
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

    // MARK: - System process detection

    private static let systemPathPrefixes = [
        "/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"
    ]

    private static let currentUser = NSUserName()

    /// True for ports owned by other users (root, _daemons) or by binaries
    /// living in system locations.
    func isSystemPort(_ port: PortInfo) -> Bool {
        if port.user != Self.currentUser {
            return true
        }
        return Self.systemPathPrefixes.contains { port.command.hasPrefix($0) }
    }

    func recomputeVisiblePorts() {
        let userPorts = activePorts.filter { !isSystemPort($0) }
        visiblePorts = hideSystemProcesses ? userPorts : activePorts
        menuBarBadgeCount = userPorts.filter { $0.type != .ide }.count
    }

    /// How many ports the hide-system filter is currently swallowing.
    var hiddenSystemPortsCount: Int {
        hideSystemProcesses ? activePorts.count - visiblePorts.count : 0
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
        viewDensity = .simple
        showMenuBarCount = true
        notificationsEnabled = true
        notificationSound = true
        historyLimit = 50
        protectedProcessSubstrings = Self.defaultProtectedProcessSubstrings
        watchedPorts = []
        guardedPorts = []
        UserDefaults.standard.set(false, forKey: DefaultsKey.didDismissHotkeyTip)
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

    deinit {
        stopAutoRefresh()
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

}
