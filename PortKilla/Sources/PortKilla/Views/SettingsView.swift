import SwiftUI
import AppKit

/// The dedicated Settings window (⌘,), styled like macOS System Settings:
/// a sidebar of categories on the left, the selected pane on the right.
/// Everything here is a preference — never an action.
struct SettingsView: View {
    @ObservedObject var portManager: PortManager
    @EnvironmentObject var appDelegate: AppDelegate

    enum Pane: String, CaseIterable, Identifiable {
        case general = "General"
        case display = "Display"
        case shortcuts = "Shortcuts"
        case protected = "Protected"
        case about = "About"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .display: return "list.bullet.rectangle.fill"
            case .shortcuts: return "keyboard.fill"
            case .protected: return "shield.lefthalf.filled"
            case .about: return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .general: return .gray
            case .display: return .blue
            case .shortcuts: return .purple
            case .protected: return .orange
            case .about: return .green
            }
        }
    }

    @State private var selection: Pane = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $selection) { pane in
                NavigationLink(value: pane) {
                    Label {
                        Text(pane.rawValue)
                    } icon: {
                        Image(systemName: pane.icon)
                            .foregroundStyle(.white)
                            .font(.system(size: 11))
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 5).fill(pane.tint))
                    }
                }
            }
            .navigationSplitViewColumnWidth(180)
            .listStyle(.sidebar)
        } detail: {
            detail(for: selection)
                .navigationTitle(selection.rawValue)
        }
        .frame(width: 620, height: 440)
    }

    @ViewBuilder
    private func detail(for pane: Pane) -> some View {
        switch pane {
        case .general:   GeneralSettings(portManager: portManager)
        case .display:   DisplaySettings(portManager: portManager)
        case .shortcuts: ShortcutsSettings()
        case .protected: ProtectedProcessListView(portManager: portManager, embedded: true)
        case .about:     AboutSettings(portManager: portManager)
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var portManager: PortManager
    @State private var launchAtLogin = LoginItem.isEnabled

    private let intervals: [(TimeInterval, String)] = [
        (0, "Manual only"), (2, "Every 2 seconds"), (5, "Every 5 seconds"),
        (10, "Every 10 seconds"), (30, "Every 30 seconds")
    ]

    var body: some View {
        Form {
            Section("Startup & Scanning") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        if LoginItem.setEnabled(newValue) { launchAtLogin = newValue }
                        else { portManager.showToast("Needs the installed .app bundle") }
                    }
                ))
                Picker("Auto refresh", selection: $portManager.refreshInterval) {
                    ForEach(intervals, id: \.0) { Text($0.1).tag($0.0) }
                }
            }

            Section("Killing") {
                Toggle("Confirm before killing a process", isOn: $portManager.confirmBeforeKill)
                Text("When off, the kill button acts immediately (Option-click always force-kills).")
                    .settingsCaption()
            }

            Section("Notifications") {
                Toggle("Notify on watched / guarded port changes", isOn: $portManager.notificationsEnabled)
                Text("Alerts when a watched port frees up or gets taken, and when a guard auto-kills.")
                    .settingsCaption()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Display

private struct DisplaySettings: View {
    @ObservedObject var portManager: PortManager

    var body: some View {
        Form {
            Section("Row density") {
                Picker("Density", selection: $portManager.viewDensity) {
                    Text("Simple").tag(PortManager.ViewDensity.clean)
                    Text("Advanced").tag(PortManager.ViewDensity.advanced)
                }
                .pickerStyle(.segmented)
                Text("Simple shows port, name, and memory. Advanced adds the command, project/container, CPU, and the process tree.")
                    .settingsCaption()
            }

            Section("List") {
                Toggle("Hide system processes", isOn: $portManager.hideSystemProcesses)
                Text("Keeps macOS daemons out of the list; a footer hint shows how many are hidden.")
                    .settingsCaption()
            }

            Section("Menu bar") {
                Toggle("Show active port count", isOn: $portManager.showMenuBarCount)
                Text("Displays the number of dev ports next to the ⚡ icon.")
                    .settingsCaption()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

private struct ShortcutsSettings: View {
    @EnvironmentObject var appDelegate: AppDelegate
    @State private var recording = false

    var body: some View {
        Form {
            Section("Global hotkey") {
                HStack {
                    Text("Open PortKilla from anywhere")
                    Spacer()
                    Text(appDelegate.hotkeyDisplay)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)
                    Button("Change…") { recording = true }
                    Button("Reset") { appDelegate.resetHotKey() }
                }
                Text("Works from any app — no Accessibility permission required.")
                    .settingsCaption()
            }

            Section("In-app shortcuts") {
                shortcutRow("Refresh", "⌘R")
                shortcutRow("Kill all (current filter)", "⌘K")
                shortcutRow("Kill selected", "⏎")
                shortcutRow("Force kill selected", "⌘⏎")
                shortcutRow("Open selected in browser", "⌘O")
                shortcutRow("Settings", "⌘,")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $recording) { HotKeyRecorderView() }
    }

    private func shortcutRow(_ title: String, _ key: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    @ObservedObject var portManager: PortManager
    @State private var showResetConfirm = false

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).map { "v\($0)" } ?? "dev"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.fill").font(.system(size: 40)).foregroundColor(.yellow)
            Text("PortKilla").font(.title2).bold()
            Text(version).foregroundColor(.secondary)

            if let newer = portManager.updateAvailableVersion {
                Button("Download v\(newer)…") { NSWorkspace.shared.open(UpdateChecker.releasesPageURL) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Check for Updates…") { portManager.checkForUpdates(manual: true) }
            }

            Divider().padding(.vertical, 6)

            Button("Reset all settings to defaults") { showResetConfirm = true }
                .foregroundColor(.red)

            Text("The macOS menu bar port manager · global hotkey opens it from anywhere.")
                .settingsCaption()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .alert("Reset all settings?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) { portManager.resetAllSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restores refresh interval, density, protected list, hotkey, and toggles to their defaults. Watched/guarded ports are cleared.")
        }
    }
}

private extension View {
    func settingsCaption() -> some View {
        self.font(.caption).foregroundColor(.secondary)
    }
}
