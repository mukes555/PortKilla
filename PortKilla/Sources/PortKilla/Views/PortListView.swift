import SwiftUI
import Foundation
import AppKit

struct PortListView: View {
    enum ListFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case dev = "Dev"
        case database = "Databases"
        case docker = "Docker"
        case tests = "Tests"

        var id: String { rawValue }
    }

    private enum ActiveSheet: Identifiable {
        case portDetail(PortInfo)
        case bulkKill
        case protectedProcesses
        case hotkeyRecorder

        var id: String {
            switch self {
            case .portDetail(let port):
                return "portDetail-\(port.id)"
            case .bulkKill:
                return "bulkKill"
            case .protectedProcesses:
                return "protectedProcesses"
            case .hotkeyRecorder:
                return "hotkeyRecorder"
            }
        }
    }

    @ObservedObject var portManager: PortManager
    @EnvironmentObject var appDelegate: AppDelegate
    @State private var hoverId: String?
    @State private var searchText = ""
    @State private var filter: ListFilter = .all
    @State private var eventMonitor: Any?
    @State private var activeSheet: ActiveSheet?
    @State private var selectedId: String?
    @State private var expandedIds: Set<String> = []
    @State private var launchAtLogin = LoginItem.isEnabled
    @AppStorage("PortKilla.didDismissHotkeyTip") private var didDismissHotkeyTip = false
    @FocusState private var isSearchFocused: Bool

    var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(version ?? "dev")"
    }

    var filteredPorts: [PortInfo] {
        var ports = portManager.visiblePorts

        switch filter {
        case .all, .tests:
            break
        case .dev:
            ports = ports.filter { $0.type.category == .web }
        case .database:
            ports = ports.filter { $0.type.category == .database }
        case .docker:
            ports = ports.filter { $0.type == .docker || $0.containerName != nil }
        }

        if searchText.isEmpty {
            return ports
        }
        return ports.filter { port in
            String(port.port).contains(searchText) ||
            port.processName.localizedCaseInsensitiveContains(searchText) ||
            port.command.localizedCaseInsensitiveContains(searchText) ||
            (port.projectName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (port.containerName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var groupedPorts: [(key: PortInfo.PortCategory, value: [PortInfo])] {
        let grouped = Dictionary(grouping: filteredPorts) { $0.type.category }
        // Sort categories logically: Web first, then IDE, then DB, then Other
        return grouped.sorted { (first, second) -> Bool in
            let order: [PortInfo.PortCategory] = [.web, .ide, .database, .other]
            let firstIndex = order.firstIndex(of: first.key) ?? 999
            let secondIndex = order.firstIndex(of: second.key) ?? 999
            return firstIndex < secondIndex
        }
    }

    var filteredTests: [TestProcessInfo] {
        if searchText.isEmpty {
            return portManager.activeTests
        }
        return portManager.activeTests.filter { test in
            test.processName.localizedCaseInsensitiveContains(searchText) ||
            test.command.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Row order as displayed, used for arrow-key navigation.
    private var visibleIdsInOrder: [String] {
        if filter == .tests {
            return filteredTests.map(\.id)
        }
        return groupedPorts.flatMap { $0.value.map(\.id) }
    }

    private var selectedPort: PortInfo? {
        guard let selectedId else { return nil }
        return filteredPorts.first { $0.id == selectedId }
    }

    private var selectedTest: TestProcessInfo? {
        guard let selectedId else { return nil }
        return filteredTests.first { $0.id == selectedId }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if let errorMessage = portManager.lastErrorMessage {
                    ErrorBannerView(message: errorMessage) {
                        portManager.lastErrorMessage = nil
                    }
                }

                headerView

                Divider()

                if filter == .tests {
                    TestRadarView(portManager: portManager, tests: filteredTests, selectedId: $selectedId)
                } else {
                    portsContentView
                }

                Divider()

                footerView
            }
            .frame(width: 500, height: 600)

            if let toastMessage = portManager.toastMessage {
                VStack {
                    Spacer()
                    ToastView(message: toastMessage)
                        .padding(.bottom, 12)
                }
                .frame(width: 500, height: 600)
                .allowsHitTesting(false)
            }
        }
        // Opaque background so list rows never sit on unpredictable popover material
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            installKeyMonitorIfNeeded()
            launchAtLogin = LoginItem.isEnabled
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .portDetail(let port):
                PortDetailView(port: port)
            case .bulkKill:
                BulkKillView(portManager: portManager)
            case .protectedProcesses:
                ProtectedProcessListView(portManager: portManager)
            case .hotkeyRecorder:
                HotKeyRecorderView()
            }
        }
    }

    // MARK: - Keyboard

    private func installKeyMonitorIfNeeded() {
        // The popover can re-show without a matching onDisappear;
        // guard so shortcuts never stack duplicate monitors.
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event) ? nil : event
        }
    }

    /// Returns true when the event was handled (and should be consumed).
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Don't hijack keys while a sheet or alert has its own focus.
        guard activeSheet == nil else { return false }

        let hasCommand = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 53: // Esc: clear the search first, then close
            if !searchText.isEmpty {
                searchText = ""
            } else {
                appDelegate.closePopover()
            }
            return true
        case 125: // ↓
            moveSelection(by: 1)
            return true
        case 126: // ↑
            moveSelection(by: -1)
            return true
        case 124: // → expands the tree — but only when not editing search text
            if searchText.isEmpty, let port = selectedPort, port.children?.isEmpty == false {
                expandedIds.insert(port.id)
                return true
            }
            return false
        case 123: // ←
            if searchText.isEmpty, let port = selectedPort {
                expandedIds.remove(port.id)
                return true
            }
            return false
        case 36: // ⏎ kills the selection; ⌘⏎ force kills
            if filter == .tests, let test = selectedTest {
                requestKillTest(test, force: hasCommand)
                return true
            }
            if let port = selectedPort {
                requestKill(port, force: hasCommand, killTree: false)
                return true
            }
            return false
        default:
            break
        }

        guard hasCommand, let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch characters {
        case "r":
            portManager.refresh(showToast: true)
            return true
        case "k":
            if filter == .tests {
                killAllTests()
            } else {
                killAllDev()
            }
            return true
        case "o":
            if let port = selectedPort {
                Browser.openLocalhost(port: port.port)
                return true
            }
            return false
        case "c":
            // Only steal ⌘C from the search field when there's nothing to copy there.
            if searchText.isEmpty, let port = selectedPort {
                Pasteboard.copy("\(port.port)")
                portManager.showToast("Copied \(port.port)")
                return true
            }
            return false
        case "q":
            NSApplication.shared.terminate(nil)
            return true
        default:
            return false
        }
    }

    private func moveSelection(by offset: Int) {
        let ids = visibleIdsInOrder
        guard !ids.isEmpty else { return }

        guard let current = selectedId, let index = ids.firstIndex(of: current) else {
            selectedId = offset >= 0 ? ids.first : ids.last
            return
        }
        let next = min(max(index + offset, 0), ids.count - 1)
        selectedId = ids[next]
    }

    // MARK: - Kill flows

    /// Single entry point for killing a port: applies the confirm-before-kill
    /// setting (with a "don't ask again" checkbox) and then delegates.
    private func requestKill(_ port: PortInfo, force: Bool, killTree: Bool) {
        if portManager.confirmBeforeKill {
            let confirmed = runKillConfirmation(
                title: "Kill Process on :\(port.port)?",
                message: "This will terminate '\(port.processName)' (PID \(port.pid))."
            )
            guard confirmed else { return }
        }
        portManager.killPort(port, force: force, killTree: killTree)
    }

    private func requestKillTest(_ test: TestProcessInfo, force: Bool = false) {
        if portManager.confirmBeforeKill {
            let confirmed = runKillConfirmation(
                title: "Kill \(test.processName)?",
                message: "This will terminate '\(test.processName)' (PID \(test.pid))."
            )
            guard confirmed else { return }
        }
        portManager.killTestProcess(test, force: force)
    }

    private func requestKillChild(_ child: PortInfo.ProcessInfo) {
        if portManager.confirmBeforeKill {
            let confirmed = runKillConfirmation(
                title: "Kill \(child.name)?",
                message: "This will terminate '\(child.name)' (PID \(child.pid))."
            )
            guard confirmed else { return }
        }
        portManager.killProcess(pid: child.pid, name: child.name)
    }

    private func runKillConfirmation(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Kill")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"

        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if confirmed, alert.suppressionButton?.state == .on {
            portManager.confirmBeforeKill = false
        }
        return confirmed
    }

    func killAllDev() {
        let devPorts = portManager.visiblePorts.filter {
            $0.type.category == .web && !portManager.isProtectedProcessName($0.processName)
        }

        if devPorts.isEmpty {
            let alert = NSAlert()
            alert.messageText = "No Dev Servers Found"
            alert.informativeText = "There are no unprotected dev server processes to kill."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let processList = devPorts.map { "• \($0.processName) (:\($0.port))" }.joined(separator: "\n")

        let alert = NSAlert()
        alert.messageText = "Kill \(devPorts.count) Dev Server\(devPorts.count == 1 ? "" : "s")?"
        alert.informativeText = "This will terminate the following processes:\n\n\(processList)\n\nAre you sure?"
        alert.addButton(withTitle: "Kill All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            portManager.killPorts(devPorts)
        }
    }

    func killAllTests() {
        let testProcesses = portManager.activeTests
        let killableTests = testProcesses.filter { !portManager.isProtectedProcessName($0.processName) }

        if killableTests.isEmpty {
            let alert = NSAlert()
            alert.messageText = "No Test Processes Found"
            alert.informativeText = testProcesses.isEmpty
                ? "There are no active test processes to kill."
                : "All active test processes are protected."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let processList = killableTests.map { "• \($0.processName) (PID: \($0.pid))" }.joined(separator: "\n")

        let alert = NSAlert()
        alert.messageText = "Kill \(killableTests.count) Test Processes?"
        alert.informativeText = "This will terminate the following processes:\n\n\(processList)\n\nAre you sure?"
        alert.addButton(withTitle: "Kill All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            portManager.killTestProcesses(killableTests)
        }
    }

    // MARK: - Header

    var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                Text("PortKilla")
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                settingsMenu
            }

            searchField

            filterChips

            if !didDismissHotkeyTip {
                hotkeyTip
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var settingsMenu: some View {
        Menu {
            Button("Refresh Now") { portManager.refresh(showToast: true) }
                .keyboardShortcut("r")

            Menu("Auto Refresh") {
                Picker("", selection: $portManager.refreshInterval) {
                    Text("Manual only").tag(TimeInterval(0))
                    Text("Every 2 seconds").tag(TimeInterval(2))
                    Text("Every 5 seconds").tag(TimeInterval(5))
                    Text("Every 10 seconds").tag(TimeInterval(10))
                    Text("Every 30 seconds").tag(TimeInterval(30))
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Divider()

            Toggle("Hide System Processes", isOn: $portManager.hideSystemProcesses)
            Toggle("Confirm Before Kill", isOn: $portManager.confirmBeforeKill)
            Toggle("Launch at Login", isOn: launchAtLoginBinding)

            Divider()

            Button("Bulk Kill…") { activeSheet = .bulkKill }
            Button("Protected Processes…") { activeSheet = .protectedProcesses }
            Button("Change Hotkey… (\(appDelegate.hotkeyDisplay))") { activeSheet = .hotkeyRecorder }
            Button("History…") { appDelegate.showHistory() }

            Divider()

            if let newer = portManager.updateAvailableVersion {
                Button("Download v\(newer)…") {
                    NSWorkspace.shared.open(UpdateChecker.releasesPageURL)
                }
            } else {
                Button("Check for Updates…") {
                    portManager.checkForUpdates(manual: true)
                }
            }

            Text("\(appVersionText) · global hotkey \(appDelegate.hotkeyDisplay)")

            Button("Quit PortKilla") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings")
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                if LoginItem.setEnabled(newValue) {
                    launchAtLogin = newValue
                } else {
                    portManager.showToast("Needs the installed .app bundle")
                }
            }
        )
    }

    private var hotkeyTip: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .font(.system(size: 10))
            Text("Tip: press \(appDelegate.hotkeyDisplay) anywhere to open PortKilla · ↑↓ select · ⏎ kill · ⌘O open in browser")
                .font(.system(size: 10))
                .lineLimit(1)
            Spacer()
            Button(action: { didDismissHotkeyTip = true }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(5)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search ports, processes…", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .focused($isSearchFocused)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }

    private var filterChips: some View {
        HStack(spacing: 6) {
            ForEach(ListFilter.allCases) { chip in
                Button(action: { filter = chip }) {
                    Text(chipLabel(chip))
                        .font(.system(size: 11, weight: filter == chip ? .semibold : .regular))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(filter == chip ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                        .foregroundColor(filter == chip ? .accentColor : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func chipLabel(_ chip: ListFilter) -> String {
        if chip == .tests && !portManager.activeTests.isEmpty {
            return "Tests (\(portManager.activeTests.count))"
        }
        return chip.rawValue
    }

    // MARK: - Content

    var portsContentView: some View {
        VStack(spacing: 0) {
            // Column Headers (leading 16pt matches the rows' tree-chevron gutter)
            HStack {
                Spacer().frame(width: 16)
                Text("Port")
                    .frame(width: 80, alignment: .leading)
                Text("Process")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Memory")
                    .frame(width: 70, alignment: .trailing)
                Text("Action")
                    .frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if showWatchedSection {
                WatchedSectionView(
                    portManager: portManager,
                    onKillRequest: { port in requestKill(port, force: false, killTree: false) }
                )
            }

            if filteredPorts.isEmpty {
                emptyStateView
            } else {
                PortListContent(
                    groupedPorts: groupedPorts,
                    portManager: portManager,
                    hoverId: $hoverId,
                    selectedId: $selectedId,
                    expandedIds: $expandedIds,
                    onSelectPort: { port in activeSheet = .portDetail(port) },
                    onKillRequest: { port, force, killTree in requestKill(port, force: force, killTree: killTree) },
                    onKillChild: { child in requestKillChild(child) }
                )
            }

            // The hide-system filter must never look like missing data
            if portManager.hiddenSystemPortsCount > 0 {
                Button(action: { portManager.hideSystemProcesses = false }) {
                    Text("\(portManager.hiddenSystemPortsCount) system port\(portManager.hiddenSystemPortsCount == 1 ? "" : "s") hidden — Show")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            }
        }
    }

    private var showWatchedSection: Bool {
        !portManager.watchedPorts.isEmpty && searchText.isEmpty && filter == .all
    }

    /// Searching a free port number gets a positive answer instead of a
    /// dead-end "no results".
    private var emptyStateView: some View {
        let searchedPort = Int(searchText.trimmingCharacters(in: .whitespaces))
        let isValidPort = searchedPort.map { (1...65535).contains($0) } ?? false
        let hiddenMatch = searchedPort.flatMap { number in
            portManager.activePorts.first { $0.port == number }
        }

        return VStack {
            Spacer()
            if isValidPort, let searchedPort {
                if let hiddenMatch {
                    // Occupied, but filtered out of the current view
                    Image(systemName: "eye.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    Text(":\(String(searchedPort)) is in use by \(hiddenMatch.processName)")
                        .foregroundColor(.primary)
                    Text("It's hidden by the current filter.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Show All") {
                        portManager.hideSystemProcesses = false
                        filter = .all
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 6)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                        .padding(.bottom, 8)
                    Text(":\(String(searchedPort)) is free")
                        .font(.headline)
                    Button(portManager.isWatched(searchedPort) ? "Watching ⭐" : "Watch :\(String(searchedPort))") {
                        portManager.toggleWatch(searchedPort)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 6)
                }
            } else {
                Image(systemName: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                Text(searchText.isEmpty ? "No active ports found" : "No results found")
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Footer

    var footerView: some View {
        VStack(spacing: 0) {
            // Status Bar
            HStack {
                if filter == .tests {
                    Text("\(portManager.activeTests.count) tests running · \(portManager.totalTestsMemory)")
                } else {
                    Text("\(filteredPorts.count) of \(portManager.visiblePorts.count) ports · \(portManager.totalPortsMemory)")
                }
                Spacer()
                // Re-render periodically so "2s ago" can't freeze at 2s forever
                TimelineView(.periodic(from: .now, by: 10)) { _ in
                    Text("Updated \(timeAgo(from: portManager.lastUpdated))")
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            HStack(spacing: 12) {
                Button(action: {
                    if filter == .tests {
                        killAllTests()
                    } else {
                        killAllDev()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text(filter == .tests ? "Kill All Tests ⌘K" : "Kill All Dev ⌘K")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(filter == .tests ? "Kill all test processes (⌘K)" : "Kill all unprotected dev servers (⌘K)")

                Spacer()

                Button(action: {
                    portManager.refresh(showToast: true)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh ⌘R")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Refresh (⌘R)")
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    func timeAgo(from date: Date) -> String {
        // The formatter says "in 0 seconds" for just-written timestamps
        if Date().timeIntervalSince(date) < 10 {
            return "just now"
        }
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}
