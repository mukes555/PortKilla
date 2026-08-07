import SwiftUI

struct ProtectedProcessListView: View {
    @ObservedObject var portManager: PortManager
    @Environment(\.dismiss) private var dismiss
    @State private var newSubstring = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailTitleBar(onClose: { dismiss() })

            Text("Protected Processes")
                .font(.headline)

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

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        // Must fit inside the 500pt-wide popover window it's presented over
        .frame(width: 460, height: 420)
    }
}
