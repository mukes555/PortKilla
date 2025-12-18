import SwiftUI

struct TestRadarView: View {
    @ObservedObject var portManager: PortManager
    @State private var hoverId: String?
    @State private var searchText = ""
    @State private var selectedTest: TestProcessInfo?

    var filteredTests: [TestProcessInfo] {
        if searchText.isEmpty {
            return portManager.activeTests
        } else {
            return portManager.activeTests.filter { test in
                test.processName.localizedCaseInsensitiveContains(searchText) ||
                test.command.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search test processes...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)

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
            if filteredTests.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    Text(searchText.isEmpty ? "No active test processes" : "No results found")
                    .foregroundColor(.secondary)
                Text("Background tests will appear here (Beta)")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.top, 4)
                Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                TestListContent(filteredTests: filteredTests, portManager: portManager, hoverId: $hoverId, selectedTest: $selectedTest)
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
    @Binding var selectedTest: TestProcessInfo?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredTests) { test in
                    TestProcessRow(test: test, manager: portManager)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(hoverId == test.id ? Color.primary.opacity(0.05) : Color.clear)
                        .onHover { isHovering in
                            hoverId = isHovering ? test.id : nil
                        }
                        .onTapGesture {
                            selectedTest = test
                        }
                    Divider()
                }
            }
        }
    }
}

struct TestDetailView: View {
    let test: TestProcessInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            }

            Divider()

            Group {
                DetailRow(label: "PID", value: "\(test.pid)")
                DetailRow(label: "Memory", value: test.memoryUsage)

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
        .frame(width: 300)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
    }
}

struct TestProcessRow: View {
    let test: TestProcessInfo
    @ObservedObject var manager: PortManager
    @State private var showConfirmation = false

    var body: some View {
        HStack {
            // Type Icon
            HStack(spacing: 4) {
                Image(systemName: test.type.icon)
                    .foregroundColor(Color(nsColor: test.type.color))
                Text(test.type.rawValue)
                    .font(.system(.caption, weight: .medium))
                    .foregroundColor(.primary)
            }
            .frame(width: 80, alignment: .leading)

            // Process & Command
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

            // Memory
            Text(test.memoryUsage)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            // Action
            HStack(spacing: 4) {
                Spacer()
                // Kill Button
                Button(action: {
                    if NSEvent.modifierFlags.contains(.option) {
                        manager.killTestProcess(test, force: true)
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
            .alert(isPresented: $showConfirmation) {
                Alert(
                    title: Text("Kill Test Process?"),
                    message: Text("Are you sure you want to kill '\(test.processName)' (PID: \(test.pid))?"),
                    primaryButton: .destructive(Text("Kill")) {
                        manager.killTestProcess(test)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
}
