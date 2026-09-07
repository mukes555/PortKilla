import PortKillaCore
import SwiftUI

/// The big window: everything the popover knows, with room to work. A
/// sidebar of views (ports, projects, agent sessions, watchlist, history),
/// the selected view in the middle, and an inspector for the chosen port.
struct WorkbenchView: View {
    enum Section: String, CaseIterable, Identifiable {
        case ports = "Ports"
        case projects = "Projects"
        case agents = "Agents"
        case watchlist = "Watchlist"
        case history = "History"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .ports: return "network"
            case .projects: return "folder"
            case .agents: return "sparkles"
            case .watchlist: return "star"
            case .history: return "clock"
            }
        }
    }

    @ObservedObject var portManager: PortManager
    @ObservedObject private var history = HistoryManager.shared
    @EnvironmentObject var appDelegate: AppDelegate
    @State var section: Section = .ports
    @State var selectedPortId: String?
    @State var searchText = ""

    init(portManager: PortManager, initialSection: Section = .ports, initialSelection: String? = nil) {
        _portManager = ObservedObject(wrappedValue: portManager)
        _section = State(initialValue: initialSection)
        _selectedPortId = State(initialValue: initialSelection)
    }

    var selectedPort: PortInfo? {
        guard let selectedPortId else { return nil }
        return portManager.activePorts.first { $0.id == selectedPortId }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                NavigationLink(value: item) {
                    Label(item.rawValue, systemImage: item.icon)
                        .badge(badge(for: item))
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 700, ideal: 820)
        } detail: {
            if let port = selectedPort {
                WorkbenchInspector(port: port, portManager: portManager)
            } else {
                inspectorPlaceholder
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1220, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .ports:
            WorkbenchPortsTable(portManager: portManager, selection: $selectedPortId, searchText: $searchText)
        case .projects:
            WorkbenchProjects(portManager: portManager, selection: $selectedPortId)
        case .agents:
            WorkbenchAgents(portManager: portManager, selection: $selectedPortId)
        case .watchlist:
            WorkbenchWatchlist(portManager: portManager, selection: $selectedPortId)
        case .history:
            HistoryView(portManager: portManager, embedded: true)
        }
    }

    private var inspectorPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("Select a port to inspect it")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func badge(for item: Section) -> Int {
        switch item {
        case .ports: return portManager.visiblePorts.count
        case .projects: return WorkbenchModel.projects(from: portManager.visiblePorts).count
        case .agents: return WorkbenchModel.agentSessions(from: portManager.visiblePorts).count
        case .watchlist: return portManager.watchedPorts.union(portManager.guardedPorts).count
        case .history: return history.events.count
        }
    }
}
