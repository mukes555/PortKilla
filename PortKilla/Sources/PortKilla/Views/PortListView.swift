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

        /// What ⌘K and the footer button kill on this filter. "All" keeps
        /// the classic "Kill All Dev" behaviour.
        var bulkKillLabel: String {
            switch self {
            case .all, .dev: return "Kill All Dev"
            case .database: return "Kill All Databases"
            case .docker: return "Kill All Docker"
            case .tests: return "Kill All Tests"
            }
        }

        func includesInBulkKill(_ port: PortInfo) -> Bool {
            switch self {
            case .all, .dev: return port.type.category == .web
            case .database: return port.type.category == .database
            case .docker: return port.type == .docker || port.containerName != nil
            case .tests: return false
            }
        }
    }

    enum ActiveSheet: Identifiable {
        case portDetail(PortInfo)
        case bulkKill

        var id: String {
            switch self {
            case .portDetail(let port):
                return "portDetail-\(port.id)"
            case .bulkKill:
                return "bulkKill"
            }
        }
    }

    @ObservedObject var portManager: PortManager
    @EnvironmentObject var appDelegate: AppDelegate
    @State private var hoverId: String?
    @State var searchText = ""
    @State var filter: ListFilter = .all
    @State var eventMonitor: Any?
    @State var activeSheet: ActiveSheet?
    @State var selectedId: String?
    @State var expandedIds: Set<String> = []
    @State var isOnScreen = false
    @State var launchAtLogin = LoginItem.isEnabled
    @AppStorage("PortKilla.didDismissHotkeyTip") var didDismissHotkeyTip = false
    @FocusState var isSearchFocused: Bool

    /// The pinned panel hosts a second copy of this view; each copy handles
    /// keys only while its own window is key.
    let hostedInPinnedWindow: Bool

    init(portManager: PortManager, initialSearchText: String = "", initialSelectedId: String? = nil, hostedInPinnedWindow: Bool = false) {
        _portManager = ObservedObject(wrappedValue: portManager)
        _searchText = State(initialValue: initialSearchText)
        _selectedId = State(initialValue: initialSelectedId)
        self.hostedInPinnedWindow = hostedInPinnedWindow
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
        let needle = searchText
        // Plain case-insensitive matching: the locale-aware variant is an
        // ICU call per field per port per keystroke.
        func matches(_ text: String?) -> Bool {
            text?.range(of: needle, options: .caseInsensitive) != nil
        }
        return ports.filter { port in
            String(port.port).contains(needle) ||
            matches(port.processName) ||
            matches(port.command) ||
            matches(port.projectName) ||
            matches(port.containerName) ||
            matches(port.agentOwner?.name)
        }
    }

    // Web first, then IDE, then DB, then Other
    private static let categoryRank: [PortInfo.PortCategory: Int] = [.web: 0, .ide: 1, .database: 2, .other: 3]

    var groupedPorts: [(key: PortInfo.PortCategory, value: [PortInfo])] {
        Dictionary(grouping: filteredPorts) { $0.type.category }
            .sorted { (Self.categoryRank[$0.key] ?? 999) < (Self.categoryRank[$1.key] ?? 999) }
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
    var visibleIdsInOrder: [String] {
        if filter == .tests {
            return filteredTests.map(\.id)
        }
        return groupedPorts.flatMap { $0.value.map(\.id) }
    }

    var selectedPort: PortInfo? {
        guard let selectedId else { return nil }
        return filteredPorts.first { $0.id == selectedId }
    }

    var selectedTest: TestProcessInfo? {
        guard let selectedId else { return nil }
        return filteredTests.first { $0.id == selectedId }
    }

    /// The popover must stay 500x600 (NSPopover follows the hosting
    /// controller's ideal size, and an unbounded list would grow with its
    /// content); only the pinned panel may be resized.
    private var maxWidth: CGFloat { hostedInPinnedWindow ? .infinity : 500 }
    private var maxHeight: CGFloat { hostedInPinnedWindow ? .infinity : 600 }

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
                    TestRadarView(
                        portManager: portManager,
                        tests: filteredTests,
                        selectedId: $selectedId,
                        onKillRequest: { test, force in requestKillTest(test, force: force) }
                    )
                } else {
                    portsContentView
                }

                Divider()

                footerView
            }
            .frame(minWidth: 500, maxWidth: maxWidth, minHeight: 600, maxHeight: maxHeight)

            if let toastMessage = portManager.toastMessage {
                VStack {
                    Spacer()
                    ToastView(message: toastMessage)
                        .padding(.bottom, 12)
                }
                .frame(minWidth: 500, maxWidth: maxWidth, minHeight: 600, maxHeight: maxHeight)
                .allowsHitTesting(false)
            }
        }
        // Opaque background so list rows never sit on unpredictable popover material
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isOnScreen = true
            installKeyMonitorIfNeeded()
            launchAtLogin = LoginItem.isEnabled
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onDisappear {
            isOnScreen = false
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
            }
        }
    }

    // MARK: - Keyboard

    // MARK: - Kill flows

    // MARK: - Header

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

            if !portManager.hasCompletedFirstScan {
                loadingStateView
            } else if filteredPorts.isEmpty {
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

    var showWatchedSection: Bool {
        !portManager.watchedPorts.isEmpty && searchText.isEmpty && filter == .all
    }

    // MARK: - Footer

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func timeAgo(from date: Date) -> String {
        // The formatter says "in 0 seconds" for just-written timestamps
        if Date().timeIntervalSince(date) < 10 {
            return "just now"
        }
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}
