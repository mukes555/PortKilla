import SwiftUI
import Foundation

struct PortListView: View {
    @ObservedObject var portManager: PortManager
    @State private var hoverId: String?
    @State private var searchText = ""
    @State private var selectedTab = 0
    @State private var eventMonitor: Any?
    @State private var selectedCategory: PortInfo.PortCategory? = nil

    var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(version ?? "dev")"
    }

    // Commands for keyboard shortcuts
    // Note: Global shortcuts are handled by AppDelegate/Menu,
    // but view-specific ones can be here if focused.

    var filteredPorts: [PortInfo] {
        let ports = portManager.activePorts

        // 1. Filter by Search Text
        let searchedPorts: [PortInfo]
        if searchText.isEmpty {
            searchedPorts = ports
        } else {
            searchedPorts = ports.filter { port in
                String(port.port).contains(searchText) ||
                port.processName.localizedCaseInsensitiveContains(searchText) ||
                (port.projectName?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // 2. Filter by Category
        if let category = selectedCategory {
            return searchedPorts.filter { $0.type.category == category }
        }

        return searchedPorts
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

    var body: some View {
        VStack(spacing: 0) {
            // Header Title
            headerView

            Divider()

            if selectedTab == 0 {
                portsContentView
            } else {
                TestRadarView(portManager: portManager)
            }

            Divider()

            // Footer Controls
            footerView
        }
        .frame(width: 400, height: 500)
        .onAppear {
            // Setup local keyboard shortcuts
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) {
                    switch event.charactersIgnoringModifiers?.lowercased() {
                    case "r":
                        portManager.refresh()
                        return nil // Consume event
                    case "k":
                        if selectedTab == 0 {
                            killAllNode()
                        } else {
                            killAllTests()
                        }
                        return nil // Consume event
                    default:
                        break
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }

    var headerView: some View {
        HStack {
            Image(systemName: "bolt.fill")
                .foregroundColor(.yellow)
            Text("PortKilla")
                .font(.headline)
                .fontWeight(.bold)

            Spacer()

            Picker("", selection: $selectedTab) {
                Text("Ports").tag(0)
                Text("Test Radar (Beta)").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 200)

            Spacer()

            Text(appVersionText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    var portsContentView: some View {
        VStack(spacing: 0) {
            // Search Bar & Filter
            HStack(spacing: 8) {
                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search ports, processes...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
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

                // Category Filter Menu
                Menu {
                    Button(action: { selectedCategory = nil }) {
                        if selectedCategory == nil {
                            Label("All Categories", systemImage: "checkmark")
                        } else {
                            Text("All Categories")
                        }
                    }
                    Divider()
                    ForEach(PortInfo.PortCategory.allCases, id: \.self) { category in
                        Button(action: { selectedCategory = category }) {
                            if selectedCategory == category {
                                Label(category.rawValue, systemImage: "checkmark")
                            } else {
                                Text(category.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: selectedCategory == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .foregroundColor(selectedCategory == nil ? .secondary : .blue)
                        .font(.system(size: 14))
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .frame(width: 20)
                .help("Filter by Category")
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)

            // Column Headers
            HStack {
                Text("Port")
                    .frame(width: 80, alignment: .leading)
                Text("Process")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Memory")
                    .frame(width: 70, alignment: .trailing)
                Text("Action")
                    .frame(width: 60, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // List
            if filteredPorts.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    Text(searchText.isEmpty ? "No active ports found" : "No results found")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                PortListContent(groupedPorts: groupedPorts, portManager: portManager, hoverId: $hoverId)
            }
        }
    }

    var footerView: some View {
        VStack(spacing: 0) {
            // Status Bar
            HStack {
                if selectedTab == 0 {
                    Text("📊 \(portManager.activePorts.count) ports active • \(portManager.totalPortsMemory)")
                } else {
                    Text("🕵️‍♂️ \(portManager.activeTests.count) tests running • \(portManager.totalTestsMemory)")
                }
                Spacer()
                Text("Last updated: \(timeAgo(from: portManager.lastUpdated))")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            HStack(spacing: 12) {
                Button(action: {
                    if selectedTab == 0 {
                        killAllNode()
                    } else {
                        killAllTests()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text(selectedTab == 0 ? "Kill All Dev" : "Kill All Tests")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(selectedTab == 0 ? "Kill all Node.js processes (Cmd+K)" : "Kill all test processes")

                Spacer()

                Button(action: {
                    portManager.refresh()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Refresh (Cmd+R)")

                // Refresh Interval Menu (Replaces Prefs)
                Menu {
                    Text("Refresh Interval")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Manual Only") {
                        portManager.refreshInterval = 0
                    }
                    Button("Every 2s") {
                        portManager.refreshInterval = 2
                    }
                    Button("Every 5s") {
                        portManager.refreshInterval = 5
                    }
                    Button("Every 10s") {
                        portManager.refreshInterval = 10
                    }
                    Button("Every 30s") {
                        portManager.refreshInterval = 30
                    }
                } label: {
                    Image(systemName: "eye")
                        .foregroundColor(portManager.refreshInterval > 0 ? .blue : .secondary)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .frame(width: 20)
                .help("Monitoring Settings")

                // History Button (Icon only)
                Button(action: {
                    openHistory()
                }) {
                    Image(systemName: "clock")
                }
                .buttonStyle(.borderless)
                .help("History")

                // Quit Button (Icon only)
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("Quit PortKilla")
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    func killAllNode() {
        let nodePorts = portManager.killablePorts(ofType: .nodejs)
        let count = nodePorts.count

        if count == 0 {
            let alert = NSAlert()
            alert.messageText = "No Node.js Processes Found"
            alert.informativeText = "There are no active Node.js processes to kill."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let processList = nodePorts.map { "• \($0.processName) (:\($0.port))" }.joined(separator: "\n")

        let alert = NSAlert()
        alert.messageText = "Kill \(count) Node.js Processes?"
        alert.informativeText = "This will terminate the following processes:\n\n\(processList)\n\nAre you sure?"
        alert.addButton(withTitle: "Kill All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            portManager.killAllPorts(ofType: .nodejs)
        }
    }

    func killAllTests() {
        let testProcesses = portManager.activeTests
        let count = testProcesses.count

        if count == 0 {
            let alert = NSAlert()
            alert.messageText = "No Test Processes Found"
            alert.informativeText = "There are no active test processes to kill."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let processList = testProcesses.map { "• \($0.processName) (PID: \($0.pid))" }.joined(separator: "\n")

        let alert = NSAlert()
        alert.messageText = "Kill \(count) Test Processes?"
        alert.informativeText = "This will terminate the following processes:\n\n\(processList)\n\nAre you sure?"
        alert.addButton(withTitle: "Kill All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Kill each test process
            for test in testProcesses {
                portManager.killTestProcess(test)
            }
        }
    }

    @EnvironmentObject var appDelegate: AppDelegate

    func openHistory() {
        appDelegate.showHistory()
    }
}

struct PortListContent: View {
    let groupedPorts: [(key: PortInfo.PortCategory, value: [PortInfo])]
    @ObservedObject var portManager: PortManager
    @Binding var hoverId: String? // Changed to String to match PortInfo.id

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedPorts, id: \.key) { category, ports in
                    PortSectionView(category: category, ports: ports, portManager: portManager, hoverId: $hoverId)
                }
            }
        }
    }
}

struct PortSectionView: View {
    let category: PortInfo.PortCategory
    let ports: [PortInfo]
    @ObservedObject var portManager: PortManager
    @Binding var hoverId: String?

    var body: some View {
        Section(header:
            HStack {
                Text(category.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        ) {
            ForEach(ports) { port in
                PortRowView(port: port, manager: portManager)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(hoverId == port.id ? Color.primary.opacity(0.05) : Color.clear)
                    .onHover { isHovering in
                        hoverId = isHovering ? port.id : nil
                    }
                Divider()
            }
        }
    }
}

struct PortRowView: View {
    let port: PortInfo
    @ObservedObject var manager: PortManager
    @State private var showConfirmation = false

    var body: some View {
        HStack {
            // Port
            HStack(spacing: 4) {
                Image(systemName: port.type.icon)
                    .foregroundColor(Color(nsColor: port.type.color))
                Text(":\(String(port.port))")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .frame(width: 80, alignment: .leading)

            // Process
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(port.processName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    if let project = port.projectName {
                        Text(project)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                }

                // Command Line
                HStack(spacing: 4) {
                    Text("└─")
                        .foregroundColor(.secondary)
                    Text(port.command)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("PID: \(port.pid)\nCommand: \(port.command)")

            // Memory
            Text(port.memoryUsage)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            // Action
            HStack(spacing: 4) {
                // Kill Button
                Button(action: {
                    // Check for Option key (Force Kill)
                    if NSEvent.modifierFlags.contains(.option) {
                        manager.killPort(port, force: true)
                    } else {
                        showConfirmation = true
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 60, alignment: .trailing)
        }
        // Move alert outside the main hierarchy to prevent hover conflicts
        .background(
            Color.clear
                .alert(isPresented: $showConfirmation) {
                    Alert(
                        title: Text("Kill Process on :\(port.port)?"),
                        message: Text("Are you sure you want to kill '\(port.processName)' (PID: \(port.pid))?"),
                        primaryButton: .destructive(Text("Kill")) {
                            manager.killPort(port)
                        },
                        secondaryButton: .cancel()
                    )
                }
        )
    }
}
