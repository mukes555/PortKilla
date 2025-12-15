import SwiftUI

struct PortListView: View {
    @StateObject private var portManager = PortManager()
    @State private var hoverId: UUID?
    
    // Commands for keyboard shortcuts
    // Note: Global shortcuts are handled by AppDelegate/Menu, 
    // but view-specific ones can be here if focused.
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Port")
                    .frame(width: 60, alignment: .leading)
                Text("Process")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Memory")
                    .frame(width: 70, alignment: .trailing)
                Text("Action")
                    .frame(width: 60, alignment: .trailing)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // List
            if portManager.activePorts.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    Text("No active ports found")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(portManager.activePorts) { port in
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
            
            Divider()
            
            // Footer Controls
            HStack(spacing: 12) {
                Button(action: {
                    killAllNode()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Kill Node")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Kill all Node.js processes (Cmd+K)")
                
                Spacer()
                
                Button(action: {
                    portManager.refresh()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh (Cmd+R)")
                
                Button(action: {
                    openPreferences()
                }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings (Cmd+,)")
                
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
        .frame(width: 400, height: 500)
    }
    
    private func killAllNode() {
        let alert = NSAlert()
        alert.messageText = "Kill All Node.js Processes?"
        alert.informativeText = "This will terminate all running Node.js development servers."
        alert.addButton(withTitle: "Kill")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            portManager.killAllPorts(ofType: .nodejs)
        }
    }
    
    private func openPreferences() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.showPreferences()
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
            Text(":\(port.port)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Color(nsColor: port.type.color))
                .frame(width: 60, alignment: .leading)
            
            // Process
            VStack(alignment: .leading, spacing: 2) {
                Text(port.processName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                if let project = port.projectName {
                    Text(project)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("PID: \(port.pid)\nCommand: \(port.command)")
            
            // Memory
            Text(port.memoryUsage)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
            
            // Action
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
            .frame(width: 60, alignment: .trailing)
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
        }
    }
}
