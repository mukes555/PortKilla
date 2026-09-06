import SwiftUI
import AppKit

struct TestRadarView: View {
    @ObservedObject var portManager: PortManager
    // Filtered by the main search field in PortListView
    let tests: [TestProcessInfo]
    @Binding var selectedId: String?
    @State private var hoverId: String?
    @State private var selectedTest: TestProcessInfo?
    /// Kill requests go up to PortListView, which owns the one confirmation
    /// flow for every kill in the app.
    let onKillRequest: (_ test: TestProcessInfo, _ force: Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Column Headers
            HStack {
                Text("Type")
                    .frame(width: 80, alignment: .leading)
                Text("Process / Command")
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
            if tests.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    Text("No active test processes")
                    .foregroundColor(.secondary)
                Text("Background tests will appear here (Beta)")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.top, 4)
                Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                TestListContent(
                    filteredTests: tests,
                    portManager: portManager,
                    hoverId: $hoverId,
                    selectedId: $selectedId,
                    onSelectTest: { test in selectedTest = test },
                    onKillRequest: onKillRequest
                )
            }
        }
        .popover(item: $selectedTest) { test in
            TestDetailView(test: test)
        }
    }
}

struct TestListContent: View {
    let filteredTests: [TestProcessInfo]
    @ObservedObject var portManager: PortManager
    @Binding var hoverId: String?
    @Binding var selectedId: String?
    let onSelectTest: (TestProcessInfo) -> Void
    let onKillRequest: (_ test: TestProcessInfo, _ force: Bool) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredTests) { test in
                        TestProcessRow(
                            test: test,
                            manager: portManager,
                            onSelect: { onSelectTest(test) },
                            onKillRequest: { force in onKillRequest(test, force) }
                        )
                            .id(test.id)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(rowBackground(for: test.id))
                            .onHover { isHovering in
                                hoverId = isHovering ? test.id : nil
                            }
                        Divider()
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

    private func rowBackground(for id: String) -> Color {
        if selectedId == id {
            return Color.accentColor.opacity(0.15)
        }
        if hoverId == id {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }
}

struct TestDetailView: View {
    let test: TestProcessInfo
    @Environment(\.dismiss) private var dismiss

    private var executablePath: String? {
        let trimmed = test.command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailTitleBar(onClose: { dismiss() })

            HStack {
                Image(systemName: test.type.icon)
                    .font(.title)
                    .foregroundColor(Color(nsColor: test.type.color))
                VStack(alignment: .leading) {
                    Text(test.processName)
                        .font(.headline)
                    Text(test.type.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Menu {
                    Button("Copy PID") { Pasteboard.copy("\(test.pid)") }
                    Button("Copy Command") { Pasteboard.copy(test.command) }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .menuStyle(BorderlessButtonMenuStyle())
            }

            Divider()

            Group {
                DetailRow(label: "PID", value: "\(test.pid)")
                DetailRow(label: "Memory", value: test.memoryUsage)
                if let exec = executablePath {
                    DetailRow(label: "Executable", value: exec)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Command")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(test.command)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                }
            }
        }
        .padding()
        .frame(width: 360, height: 360)
    }
}

struct TestProcessRow: View {
    let test: TestProcessInfo
    @ObservedObject var manager: PortManager
    let onSelect: () -> Void
    let onKillRequest: (_ force: Bool) -> Void

    var body: some View {
        HStack {
            // Type Icon
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: test.type.icon)
                        .foregroundColor(Color(nsColor: test.type.color))
                    Text(test.type.rawValue)
                        .font(.system(.caption, weight: .medium))
                        .foregroundColor(.primary)
                }
                .frame(width: 80, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(test.processName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    HStack(spacing: 4) {
                        Text("└─")
                            .foregroundColor(.secondary)
                        Text(test.command)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("PID: \(test.pid)\nCommand: \(test.command)")

                // Tests are exactly where CPU% matters (runaway watchers)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(test.memoryUsage)
                        .font(.system(size: 11, design: .monospaced))
                    Text(String(format: "%.0f%% cpu", test.cpuPercent))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(test.cpuPercent > 80 ? .orange : .secondary)
                }
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }

            // Action
            HStack(spacing: 4) {
                Spacer()
                // Kill Button
                Button(action: {
                    // Option = force kill (SIGKILL)
                    onKillRequest(NSEvent.modifierFlags.contains(.option))
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kill \(test.processName)")
                .help("Click to kill. Option+Click to force kill.")
            }
            .frame(width: 60, alignment: .trailing)
        }
        .contextMenu {
            Button("Copy PID") {
                Pasteboard.copy("\(test.pid)")
            }
            Button("Copy Command") {
                Pasteboard.copy(test.command)
            }
        }
    }
}
