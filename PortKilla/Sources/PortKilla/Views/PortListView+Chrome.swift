import SwiftUI
import Foundation
import AppKit

// MARK: - Header, settings menu, footer, empty state
extension PortListView {

    var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(version ?? "dev")"
    }

    var headerView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                Text("PortKilla")
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                densityToggle
                overflowMenu
                settingsButton
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

    /// Modern segmented capsule to switch row density.
    var densityToggle: some View {
        DensityToggle(density: $portManager.viewDensity)
    }

    /// Overflow menu: actions only (never settings — those live in ⚙︎).
    var overflowMenu: some View {
        Menu {
            Button("Refresh") { portManager.refresh(showToast: true) }
                .keyboardShortcut("r")
            Button("Bulk Kill…") { activeSheet = .bulkKill }
            Button(appDelegate.isPinned ? "Unpin Floating Window" : "Pin as Floating Window") {
                appDelegate.togglePinnedWindow()
            }
            Button("History…") { appDelegate.showHistory() }

            Divider()

            if let newer = portManager.updateAvailableVersion {
                Button("Download v\(newer)…") { NSWorkspace.shared.open(UpdateChecker.releasesPageURL) }
            }
            Button("Quit PortKilla") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Actions")
    }

    /// Gear opens the dedicated Settings window — settings only, no actions.
    var settingsButton: some View {
        Button {
            appDelegate.openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(",", modifiers: .command)
        .help("Settings")
    }

    var launchAtLoginBinding: Binding<Bool> {
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

    var hotkeyTip: some View {
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

    var searchField: some View {
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

    var filterChips: some View {
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

    func chipLabel(_ chip: ListFilter) -> String {
        if chip == .tests && !portManager.activeTests.isEmpty {
            return "Tests (\(portManager.activeTests.count))"
        }
        return chip.rawValue
    }

    /// Before the first scan lands nothing is known yet; "no ports" would
    /// be a claim made without data.
    var loadingStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text("Scanning ports…")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Searching a free port number gets a positive answer instead of a
    /// dead-end "no results".
    var emptyStateView: some View {
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

    var footerView: some View {
        VStack(spacing: 0) {
            // Status Bar
            HStack {
                if filter == .tests {
                    Text("\(portManager.activeTests.count) tests running · \(portManager.totalTestsMemory)")
                } else {
                    Text("\(filteredPorts.count) of \(portManager.visiblePorts.count) ports · \(portManager.totalPortsMemory)")
                }
                if portManager.isCompatibilityScan {
                    Text("· compatibility scan")
                        .help("The native scanner is unavailable here, so PortKilla is reading ports through lsof. It works, but each refresh is slower.")
                }
                Spacer()
                UpdatedLabel(clock: portManager.clock, isOnScreen: isOnScreen)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            HStack(spacing: 12) {
                Button(action: { killAllForCurrentFilter() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("\(filter.bulkKillLabel) ⌘K")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("\(filter.bulkKillLabel): unprotected processes on this filter (⌘K)")

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
}

/// The footer's "Updated 2s ago". Observes the refresh clock on its own so a
/// scan landing re-renders this label and nothing else, and only ticks while
/// the list is on screen (the hosting view outlives the popover).
struct UpdatedLabel: View {
    @ObservedObject var clock: RefreshClock
    let isOnScreen: Bool

    var body: some View {
        if isOnScreen {
            // Re-render periodically so "2s ago" can't freeze at 2s forever
            TimelineView(.periodic(from: .now, by: 10)) { _ in
                Text("Updated \(PortListView.timeAgo(from: clock.lastUpdated))")
            }
        } else {
            Text("Updated \(PortListView.timeAgo(from: clock.lastUpdated))")
        }
    }
}
