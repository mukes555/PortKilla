import SwiftUI

struct ProtectedProcessListView: View {
    @ObservedObject var portManager: PortManager
    /// True when hosted inside the Settings window (no faux title bar / Close).
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var newSubstring = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !embedded {
                DetailTitleBar(onClose: { dismiss() })

                Text("Protected Processes")
                    .font(.headline)
            }

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

                if !embedded {
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(FixedSizeIf(active: !embedded, width: 460, height: 420))
    }
}

/// Applies a fixed frame only when not embedded (embedded fills the tab).
private struct FixedSizeIf: ViewModifier {
    let active: Bool
    let width: CGFloat
    let height: CGFloat
    func body(content: Content) -> some View {
        if active {
            content.frame(width: width, height: height)
        } else {
            content
        }
    }
}
