import AppKit
import PortKillaCore
import SwiftUI

/// Settings > Agents: the AI tools this Mac has, the guard's one knob,
/// setting a project up with a click per step (what `portkilla setup`
/// does), and port leases.
struct AgentsSettings: View {
    @ObservedObject var portManager: PortManager
    @AppStorage(DefaultsKey.setupProject, store: AppDelegate.preferenceDefaults) private var projectPath = ""
    @State private var report: DoctorAgents.Report?
    @State private var steps: [CLISetup.Step] = []
    @State private var outcomes: [String: CLISetup.Outcome] = [:]
    @State private var applying: Set<String> = []
    @State private var leases: [Reservation] = []

    /// The chosen folder, only while it exists; nothing defaults to home.
    private var project: URL? {
        Self.projectFolder(projectPath)
    }

    static func projectFolder(_ path: String) -> URL? {
        var isDirectory: ObjCBool = false
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path)
    }

    var body: some View {
        Form {
            Section("Tools on this Mac") {
                if let report {
                    ForEach(report.agents, id: \.name) { tool in
                        toolRow(tool)
                    }
                } else {
                    Text("Looking…").settingsCaption()
                }
                Button("Refresh") { loadReport() }
                    .controlSize(.small)
            }

            Section("The guard") {
                Toggle("Refuse agents a server nobody claims", isOn: $portManager.guardRefusesUnclaimed)
                Text("Most unclaimed servers are a person's. On, an agent must ask (or start its own server with PORTKILLA_OWNER set); off, it may stop one like a person. Another agent's running server is always refused. The CLI and the MCP server follow this switch; it is a preference on this Mac, not a lock against an agent with a shell.")
                    .settingsCaption()
            }

            Section("Set up a project") {
                HStack {
                    Text("Project folder")
                    Spacer()
                    Text(project?.path ?? "none chosen")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(project?.path ?? "Rule files need a project folder")
                    Button("Choose…") { chooseProject() }
                        .controlSize(.small)
                }
                ForEach(steps, id: \.title) { step in
                    stepRow(step)
                }
                Text("Rule files tell each tool to free ports through PortKilla; the MCP registration gives it the guard as tools. Nothing is written or run until you click Apply, and rule files go only into the folder chosen here.")
                    .settingsCaption()
            }

            Section("Leases") {
                Picker("Default lease length", selection: $portManager.leaseDefaultTTL) {
                    ForEach(Self.leaseLengths(including: portManager.leaseDefaultTTL), id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                Text("Used by `portkilla reserve` and the MCP reserve_port tool when no length is given. `exec` leases last as long as the command runs.")
                    .settingsCaption()
                if leases.isEmpty {
                    Text("No leases right now. Agents take one with `portkilla exec --free-port` or `portkilla reserve`; a lease keeps other agents off the port until it expires.")
                        .settingsCaption()
                } else {
                    ForEach(leases) { lease in
                        leaseRow(lease)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadReport()
            loadLeases()
        }
        .onChange(of: projectPath) { _ in loadReport() }
    }

    // MARK: - Rows

    private func toolRow(_ tool: DoctorAgents.Status) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.name).fontWeight(.medium)
                Text(tool.session).settingsCaption()
            }
            Spacer()
            if tool.running > 0 {
                Chip(icon: "sparkles", text: "running \(tool.running)", tint: .chipTeal)
            } else if let path = tool.installedAt {
                Chip(icon: "checkmark", text: "installed", tint: .secondary)
                    .help(path)
            } else {
                Text("not found").settingsCaption()
            }
        }
    }

    private func stepRow(_ step: CLISetup.Step) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(step.title).fontWeight(.medium)
                Spacer()
                switch step.kind {
                case .note where Self.isCommand(step.detail):
                    Button("Copy") {
                        Pasteboard.copy(step.detail.components(separatedBy: "\n")[0])
                        portManager.showToast("Copied")
                    }
                    .controlSize(.small)
                case .note:
                    EmptyView()
                case .writeRules where project == nil:
                    Text("choose a folder first").settingsCaption()
                case .writeRules, .runCommand:
                    Button(applying.contains(step.title) ? "Applying…" : "Apply") { apply(step) }
                        .controlSize(.small)
                        .disabled(applying.contains(step.title))
                }
            }
            Text(step.detail)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            if let outcome = outcomes[step.title] {
                Text(outcome.message)
                    .font(.caption)
                    .foregroundColor(outcome.ok ? .green : .red)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }

    private func leaseRow(_ lease: Reservation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock").foregroundColor(.chipPurple)
            Text(":\(String(lease.port))")
                .font(.system(.body, design: .monospaced))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(lease.describedHolder) \(lease.expiryDescription())").font(.callout)
                if let reason = lease.reason {
                    Text(reason).settingsCaption()
                }
            }
            Spacer()
            Button("Release") {
                _ = ReservationStore.shared.release(port: lease.port, by: nil, force: true)
                loadLeases()
            }
            .controlSize(.small)
        }
    }

    // MARK: - Actions

    /// The doctor captures the process table and the plan asks the
    /// diagnostics about PATH: both off the main thread, once per visit
    /// and per folder change, never per render.
    private func loadReport() {
        let folder = project ?? FileManager.default.homeDirectoryForCurrentUser
        DispatchQueue.global(qos: .userInitiated).async {
            let found = DoctorAgents.report()
            let planned = CLISetup.plan(agents: found, project: folder)
            DispatchQueue.main.async {
                report = found
                steps = planned
            }
        }
    }

    private func loadLeases() {
        leases = ReservationStore.shared.all()
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use this folder"
        panel.directoryURL = project
        if panel.runModal() == .OK, let url = panel.url {
            projectPath = url.path
            outcomes = [:]
        }
    }

    /// Writes a rule file or runs the tool's registration; the outcome
    /// stays under the step until the project changes.
    private func apply(_ step: CLISetup.Step) {
        // Rule files need the chosen folder; a registration needs none.
        if case .writeRules = step.kind, project == nil { return }
        let target = project ?? FileManager.default.homeDirectoryForCurrentUser
        applying.insert(step.title)
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = CLISetup.apply(step, project: target)
            DispatchQueue.main.async {
                applying.remove(step.title)
                outcomes[step.title] = outcome
                portManager.showToast(outcome.ok ? "Done: \(step.title)" : "Failed: \(step.title)")
            }
        }
    }

    // MARK: - Choices

    struct LeaseLength: Equatable {
        let seconds: TimeInterval
        let label: String
    }

    /// The usual lengths, plus whatever is set when it is not one of them.
    static func leaseLengths(including current: TimeInterval) -> [LeaseLength] {
        var options = [
            LeaseLength(seconds: 5 * 60, label: "5 minutes"),
            LeaseLength(seconds: 10 * 60, label: "10 minutes"),
            LeaseLength(seconds: 30 * 60, label: "30 minutes"),
            LeaseLength(seconds: 60 * 60, label: "1 hour"),
            LeaseLength(seconds: 4 * 60 * 60, label: "4 hours"),
        ]
        if !options.contains(where: { $0.seconds == current }) {
            options.append(LeaseLength(seconds: current, label: ElapsedFormat.humanize(seconds: Int(current)) ?? "\(Int(current)) s"))
            options.sort { $0.seconds < $1.seconds }
        }
        return options
    }

    /// A note that starts with a command is worth a Copy button.
    static func isCommand(_ detail: String) -> Bool {
        let first = detail.components(separatedBy: "\n")[0]
        return first.hasPrefix("portkilla ") || first.hasPrefix("claude ") || first.contains("mcp")
    }
}

private extension View {
    func settingsCaption() -> some View {
        self.font(.caption).foregroundColor(.secondary)
    }
}
