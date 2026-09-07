import PortKillaCore
import SwiftUI

/// Three pages on first launch: what the app shows, how agents are kept
/// from killing each other, and how to set the agents up. Skippable, and
/// available again from the menu.
struct TourView: View {
    @ObservedObject var portManager: PortManager
    let onFinish: () -> Void
    @EnvironmentObject var appDelegate: AppDelegate
    @AppStorage(DefaultsKey.didFinishTour) private var didFinishTour = false
    @State private var page = 0

    private let pageCount = 3

    var body: some View {
        VStack(spacing: 16) {
            Group {
                switch page {
                case 0: portsPage
                case 1: guardPage
                default: setupPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }

            HStack {
                Button("Skip") { finish() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if page > 0 {
                    Button("Back") { page -= 1 }
                }
                Button(page == pageCount - 1 ? "Done" : "Next") {
                    if page == pageCount - 1 { finish() } else { page += 1 }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func finish() {
        didFinishTour = true
        onFinish()
    }

    private var portsPage: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 44))
                .foregroundColor(.yellow)
            Text("Every port, at a glance")
                .font(.title2.weight(.semibold))
            Text("PortKilla lists every listening port with its process, project, memory, who is connected, and which AI agent started it. Press \(appDelegate.hotkeyDisplay) anywhere to open it.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Text("Type what you mean in the search field: kill 3000, open 5173, watch 8080, free port, or > for commands.")
                .font(.callout)
                .multilineTextAlignment(.center)
        }
    }

    private var guardPage: some View {
        VStack(spacing: 12) {
            MascotView(mood: .onGuard, size: 84)
            Text("Agents don't kill each other")
                .font(.title2.weight(.semibold))
            Text("PortKilla knows which agent session started each server. An agent that asks to stop another agent's server, or a server nobody claims, is refused and told why. You get a notification and decide.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Text("People are never refused: the app warns, you choose.")
                .font(.callout)
                .multilineTextAlignment(.center)
        }
    }

    private var setupPage: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
            Text("Set up your agents")
                .font(.title2.weight(.semibold))
            Text("Homebrew put `portkilla` on your PATH. Give each agent the snippet that tells it to free ports through PortKilla, and register the MCP server.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            VStack(spacing: 8) {
                copyRow("portkilla agent-docs --write", note: "adds the snippet to CLAUDE.md in the current project")
                copyRow("portkilla mcp --setup", note: "prints the MCP registration for Claude Code, Cursor, Codex")
                copyRow("portkilla doctor --agents", note: "shows how every tool on this Mac is recognised")
            }
            Button("Open the Workbench") {
                finish()
                appDelegate.openWorkbench()
            }
            .buttonStyle(.bordered)
        }
    }

    private func copyRow(_ command: String, note: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(command).font(.system(.callout, design: .monospaced))
                Text(note).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Copy") {
                Pasteboard.copy(command)
                portManager.showToast("Copied")
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }
}
