import PortKillaCore
import SwiftUI

/// The scrolling list: one section per category, rows inside.
struct PortListContent: View {
    let groupedPorts: [(key: PortInfo.PortCategory, value: [PortInfo])]
    @ObservedObject var portManager: PortManager
    @Binding var hoverId: String?
    @Binding var selectedId: String?
    @Binding var expandedIds: Set<String>
    let onSelectPort: (PortInfo) -> Void
    let onKillRequest: (PortInfo, _ force: Bool, _ killTree: Bool) -> Void
    let onKillChild: (PortInfo.ProcessInfo) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedPorts, id: \.key) { category, ports in
                        PortSectionView(
                            category: category,
                            ports: ports,
                            portManager: portManager,
                            hoverId: $hoverId,
                            selectedId: $selectedId,
                            expandedIds: $expandedIds,
                            onSelectPort: onSelectPort,
                            onKillRequest: onKillRequest,
                            onKillChild: onKillChild
                        )
                    }
                }
            }
            .onChange(of: selectedId) { newValue in
                if let newValue {
                    proxy.scrollTo(newValue)
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
    @Binding var selectedId: String?
    @Binding var expandedIds: Set<String>
    let onSelectPort: (PortInfo) -> Void
    let onKillRequest: (PortInfo, _ force: Bool, _ killTree: Bool) -> Void
    let onKillChild: (PortInfo.ProcessInfo) -> Void

    var body: some View {
        Section(header: SectionHeader(title: category.rawValue, count: ports.count, tint: Color(nsColor: category.color))) {
            ForEach(ports) { port in
                PortRowView(
                    port: port,
                    density: portManager.viewDensity,
                    isProtected: portManager.isProtectedProcessName(port.processName),
                    isWatched: portManager.isWatched(port.port),
                    isTerminating: portManager.terminatingPids.contains(port.pid),
                    isHovered: hoverId == port.id,
                    isSelected: selectedId == port.id,
                    manager: portManager,
                    isExpanded: expansionBinding(for: port.id),
                    onSelect: { onSelectPort(port) },
                    onKillRequest: { force, killTree in onKillRequest(port, force, killTree) },
                    onKillChild: onKillChild
                )
                    .id(port.id)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(rowBackground(for: port.id))
                    .onHover { isHovering in
                        hoverId = isHovering ? port.id : nil
                    }
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                Divider()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: ports.map(\.id))
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedIds.contains(id) },
            set: { expanded in
                if expanded {
                    expandedIds.insert(id)
                } else {
                    expandedIds.remove(id)
                }
            }
        )
    }

    private func rowBackground(for id: String) -> Color {
        if selectedId == id {
            return Color.accentColor.opacity(0.15)
        }
        if hoverId == id {
            return Color.accentColor.opacity(0.06)
        }
        return Color.clear
    }
}
