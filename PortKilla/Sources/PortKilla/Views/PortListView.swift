import SwiftUI
import Foundation
import AppKit

struct PortListView: View {
    private enum ActiveSheet: Identifiable {
        case portDetail(PortInfo)

        var id: String {
            switch self {
            case .portDetail(let port):
                return "portDetail-\(port.id)"
            }
        }
    }

    @ObservedObject var portManager: PortManager
    @State private var hoverId: String?
    @State private var searchText = ""
    @State private var selectedTab = 0
    @State private var eventMonitor: Any?
    @State private var selectedCategory: PortInfo.PortCategory? = nil
    @State private var activeSheet: ActiveSheet?

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
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if let errorMessage = portManager.lastErrorMessage {
                    ErrorBannerView(message: errorMessage) {
                        portManager.lastErrorMessage = nil
                    }
                }

                headerView

                Divider()

                switch selectedTab {
                case 0:
                    portsContentView
                case 1:
                    TestRadarView(portManager: portManager)
                case 2:
                    AdvancedView(portManager: portManager)
                default:
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
        .onAppear {
            if selectedTab > 2 {
                selectedTab = 0
            }
            // Setup local keyboard shortcuts
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) {
                    switch event.charactersIgnoringModifiers?.lowercased() {
                    case "r":
                        portManager.refresh(showToast: true)
                        return nil // Consume event
                    case "k":
                        if selectedTab == 0 {
                            killAllNode()
                        } else if selectedTab == 1 {
                            killAllTests()
                        } else {
                            return event
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .portDetail(let port):
                PortDetailView(port: port)
            }
        }
    }

    var headerView: some View {
        VStack(spacing: 6) {
            DetailTitleBar {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 12)

            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                Text("PortKilla")
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer()

                Picker("", selection: $selectedTab) {
                    Text("Ports").tag(0)
                    Text("Test Radar").tag(1)
                    Text("Advanced").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 260)

                Spacer()

                HStack(spacing: 8) {
                    Text(appVersionText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .padding(.top, 8)
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
                PortListContent(
                    groupedPorts: groupedPorts,
                    portManager: portManager,
                    hoverId: $hoverId,
                    onSelectPort: { port in activeSheet = .portDetail(port) }
                )
            }
        }
    }


    var footerView: some View {
        VStack(spacing: 0) {
            // Status Bar
            HStack {
                if selectedTab == 0 {
                    Text("📊 \(portManager.activePorts.count) ports active • \(portManager.totalPortsMemory)")
                } else if selectedTab == 1 {
                    Text("🕵️‍♂️ \(portManager.activeTests.count) tests running • \(portManager.totalTestsMemory)")
                } else {
                    Text("📊 \(portManager.activePorts.count) ports active • \(portManager.totalPortsMemory)")
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
                        Text(selectedTab == 0 ? "Kill All Dev ⌘K" : "Kill All Tests ⌘K")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(selectedTab == 0 ? "Kill all Node.js processes (Cmd+K)" : "Kill all test processes")

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
                .help("Refresh (Cmd+R)")

                // History Button (Icon only)
                Button(action: {
                    openHistory()
                }) {
                    Image(systemName: "clock")
                }
                .buttonStyle(.borderless)
                .help("History")
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
        let killableTests = testProcesses.filter { !portManager.isProtectedProcessName($0.processName) }
        let count = killableTests.count

        if count == 0 {
            let alert = NSAlert()
            alert.messageText = "No Test Processes Found"
            if testProcesses.isEmpty {
                alert.informativeText = "There are no active test processes to kill."
            } else {
                alert.informativeText = "All active test processes are protected."
            }
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let processList = killableTests.map { "• \($0.processName) (PID: \($0.pid))" }.joined(separator: "\n")

        let alert = NSAlert()
        alert.messageText = "Kill \(count) Test Processes?"
        alert.informativeText = "This will terminate the following processes:\n\n\(processList)\n\nAre you sure?"
        alert.addButton(withTitle: "Kill All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Kill each test process
            for test in killableTests {
                portManager.killTestProcess(test)
            }
        }
    }

    @EnvironmentObject var appDelegate: AppDelegate

    func openHistory() {
        appDelegate.showHistory()
    }
}

struct AdvancedView: View {
    private enum NestedSheet: Identifiable {
        case protectedProcesses
        case bulkKill

        var id: String {
            switch self {
            case .protectedProcesses:
                return "protectedProcesses"
            case .bulkKill:
                return "bulkKill"
            }
        }
    }

    @ObservedObject var portManager: PortManager
    @State private var nestedSheet: NestedSheet?

    private var refreshIntervalOptions: [(value: TimeInterval, title: String)] {
        [
            (0, "Manual only"),
            (2, "Every 2 seconds"),
            (5, "Every 5 seconds"),
            (10, "Every 10 seconds"),
            (30, "Every 30 seconds")
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Refresh Settings Card
                AdvancedCard(title: "Refresh Settings", icon: "arrow.clockwise") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Auto Refresh")
                            Spacer()
                            Picker("", selection: $portManager.refreshInterval) {
                                ForEach(refreshIntervalOptions, id: \.value) { option in
                                    Text(option.title).tag(option.value)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 160)
                        }

                        Divider()

                        Button(action: {
                            portManager.refresh(showToast: true)
                        }) {
                            ShortcutRow(title: "Manual Refresh", shortcut: "⌘R")
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Tools Card
                AdvancedCard(title: "Tools", icon: "hammer.fill") {
                    VStack(spacing: 16) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bulk Kill")
                                    .fontWeight(.medium)
                                Text("Kill by port range, project, or command.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Open…") { nestedSheet = .bulkKill }
                                .buttonStyle(.borderedProminent)
                        }

                        Divider()

                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Protected Processes")
                                    .fontWeight(.medium)
                                Text("\(portManager.protectedProcessSubstrings.count) rules active.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Manage…") { nestedSheet = .protectedProcesses }
                                .buttonStyle(.bordered)
                        }
                    }
                }

                // Shortcuts Card
                AdvancedCard(title: "Keyboard Shortcuts", icon: "keyboard") {
                    VStack(spacing: 12) {
                        ShortcutRow(title: "Kill All (current tab)", shortcut: "⌘K")
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .sheet(item: $nestedSheet) { sheet in
            switch sheet {
            case .bulkKill:
                BulkKillView(portManager: portManager)
            case .protectedProcesses:
                ProtectedProcessListView(portManager: portManager)
            }
        }
    }
}

struct AdvancedCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
            }
            .padding(.bottom, 4)

            content
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

struct ShortcutRow: View {
    let title: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
    }
}

struct PortListContent: View {
    let groupedPorts: [(key: PortInfo.PortCategory, value: [PortInfo])]
    @ObservedObject var portManager: PortManager
    @Binding var hoverId: String? // Changed to String to match PortInfo.id
    let onSelectPort: (PortInfo) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedPorts, id: \.key) { category, ports in
                    PortSectionView(
                        category: category,
                        ports: ports,
                        portManager: portManager,
                        hoverId: $hoverId,
                        onSelectPort: onSelectPort
                    )
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
    let onSelectPort: (PortInfo) -> Void

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
                PortRowView(port: port, manager: portManager) {
                    onSelectPort(port)
                }
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
    let onSelect: () -> Void

    var body: some View {
        HStack {
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
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }

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
        .contextMenu {
            Button("Show Details") {
                onSelect()
            }
            Divider()
            Button("Copy Port") {
                copyToPasteboard(":\(port.port)")
            }
            Button("Copy PID") {
                copyToPasteboard("\(port.pid)")
            }
            Button("Copy Command") {
                copyToPasteboard(port.command)
            }
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

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.85))
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.85))
            .cornerRadius(8)
    }
}

struct PortDetailView: View {
    let port: PortInfo
    @Environment(\.dismiss) private var dismiss

    private var executablePath: String? {
        let trimmed = port.command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailTitleBar(onClose: { dismiss() })

            HStack(alignment: .top) {
                Image(systemName: port.type.icon)
                    .font(.title2)
                    .foregroundColor(Color(nsColor: port.type.color))

                VStack(alignment: .leading, spacing: 2) {
                    Text(port.processName)
                        .font(.headline)
                    Text(":\(port.port) • PID \(port.pid)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Menu {
                    Button("Copy Port") { copyToPasteboard(":\(port.port)") }
                    Button("Copy PID") { copyToPasteboard("\(port.pid)") }
                    Button("Copy Command") { copyToPasteboard(port.command) }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .menuStyle(BorderlessButtonMenuStyle())
            }

            Divider()

            Group {
                DetailRow(label: "User", value: port.user)
                DetailRow(label: "Memory", value: port.memoryUsage)
                DetailRow(label: "Type", value: port.type.rawValue)
                if let project = port.projectName {
                    DetailRow(label: "Project", value: project)
                }
                if let exec = executablePath {
                    DetailRow(label: "Executable", value: exec)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Command")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(port.command.isEmpty ? "(No command available)" : port.command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
            }

            Spacer()
        }
        .padding()
        .frame(width: 460, height: 420)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct DetailTitleBar: View {
    let onClose: () -> Void
    @State private var isHoveringClose = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                    if isHoveringClose {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.black.opacity(0.7))
                    }
                }
            }
            .buttonStyle(.plain)
            .onHover { isHoveringClose = $0 }

            Circle()
                .fill(Color.yellow)
                .frame(width: 12, height: 12)
                .opacity(0.7)

            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
                .opacity(0.7)

            Spacer()
        }
        .padding(.top, 4)
        .padding(.leading, 2)
    }
}

struct ProtectedProcessListView: View {
    @ObservedObject var portManager: PortManager
    @Environment(\.dismiss) private var dismiss
    @State private var newSubstring = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailTitleBar(onClose: { dismiss() })

            Text("Protected Processes")
                .font(.headline)

            Text("Bulk actions skip any process whose name contains one of these substrings.")
                .font(.caption)
                .foregroundColor(.secondary)

            List {
                ForEach(portManager.protectedProcessSubstrings, id: \.self) { item in
                    HStack {
                        Text(item)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(action: {
                            portManager.protectedProcessSubstrings.removeAll { $0 == item }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)

            HStack(spacing: 8) {
                TextField("Add substring (e.g. \"xcode\")", text: $newSubstring)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Add") {
                    let candidate = newSubstring.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !candidate.isEmpty else { return }
                    guard !portManager.protectedProcessSubstrings.contains(candidate) else {
                        newSubstring = ""
                        return
                    }
                    portManager.protectedProcessSubstrings.append(candidate)
                    newSubstring = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newSubstring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack {
                Button("Reset Defaults") {
                    portManager.resetProtectedProcessSubstrings()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520, height: 420)
    }
}

struct BulkKillView: View {
    @ObservedObject var portManager: PortManager
    @Environment(\.dismiss) private var dismiss

    @State private var minPortText = ""
    @State private var maxPortText = ""
    @State private var projectContains = ""
    @State private var commandContains = ""
    @State private var includeProtected = false
    @State private var forceKill = false

    private var minPort: Int? {
        let trimmed = minPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    private var maxPort: Int? {
        let trimmed = maxPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    private var isPortRangeValid: Bool {
        if let minPort, let maxPort {
            return minPort <= maxPort
        }
        return true
    }

    private var matchingPorts: [PortInfo] {
        if !isPortRangeValid {
            return []
        }

        let projectNeedle = projectContains.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandNeedle = commandContains.trimmingCharacters(in: .whitespacesAndNewlines)

        return portManager.activePorts.filter { port in
            if !includeProtected && portManager.isProtectedProcessName(port.processName) {
                return false
            }

            if let minPort, port.port < minPort {
                return false
            }
            if let maxPort, port.port > maxPort {
                return false
            }

            if !projectNeedle.isEmpty {
                guard let projectName = port.projectName else { return false }
                if !projectName.localizedCaseInsensitiveContains(projectNeedle) {
                    return false
                }
            }

            if !commandNeedle.isEmpty {
                if !port.command.localizedCaseInsensitiveContains(commandNeedle) {
                    return false
                }
            }

            return true
        }
        .sorted { $0.port < $1.port }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailTitleBar(onClose: { dismiss() })

            Text("Bulk Kill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port Range")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            TextField("Min", text: $minPortText)
                                .frame(width: 80)
                            Text("to")
                                .foregroundColor(.secondary)
                            TextField("Max", text: $maxPortText)
                                .frame(width: 80)
                        }
                    }

                    Divider()
                        .frame(height: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Name Contains")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. webapp", text: $projectContains)
                            .frame(width: 220)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Command Contains")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. vite", text: $commandContains)
                            .frame(width: 220)
                    }
                }

                if !isPortRangeValid {
                    Text("Port range is invalid (min must be ≤ max).")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack(spacing: 16) {
                    Toggle("Include protected processes", isOn: $includeProtected)
                    Toggle("Force (SIGKILL)", isOn: $forceKill)
                }
                .toggleStyle(.checkbox)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Matches (\(matchingPorts.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if matchingPorts.isEmpty {
                    Text("No ports match the current rules.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 28)
                } else {
                    List(matchingPorts) { port in
                        HStack(spacing: 10) {
                            Text(":\(port.port)")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 70, alignment: .leading)
                            Text(port.processName)
                                .lineLimit(1)
                            if let project = port.projectName {
                                Text(project)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("PID \(port.pid)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .listStyle(.plain)
                }
            }

            Spacer()

            HStack {
                Spacer()

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Kill \(matchingPorts.count)") {
                    let count = matchingPorts.count
                    if count == 0 {
                        return
                    }

                    let listText = matchingPorts.prefix(12).map { "• \($0.processName) (:\($0.port))" }.joined(separator: "\n")
                    let suffix = count > 12 ? "\n\n…and \(count - 12) more." : ""

                    let alert = NSAlert()
                    alert.messageText = "Kill \(count) Process\(count == 1 ? "" : "es")?"
                    alert.informativeText = "This will terminate the following:\n\n\(listText)\(suffix)\n\nAre you sure?"
                    alert.addButton(withTitle: "Kill")
                    alert.addButton(withTitle: "Cancel")
                    alert.alertStyle = .warning

                    if alert.runModal() == .alertFirstButtonReturn {
                        portManager.killPorts(matchingPorts, force: forceKill)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(matchingPorts.isEmpty || !isPortRangeValid)
            }
        }
        .padding()
        .frame(width: 820, height: 520)
    }
}
