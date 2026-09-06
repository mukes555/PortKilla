import PortKillaCore
import SwiftUI

/// A modern segmented "radio" toggle: a pill with a sliding selection.
/// Simple ⟷ Advanced row density.
struct DensityToggle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var density: PortManager.ViewDensity
    @Namespace private var slider

    var body: some View {
        HStack(spacing: 0) {
            segment("Simple", icon: "list.bullet", value: .simple)
            segment("Advanced", icon: "list.bullet.rectangle", value: .advanced)
        }
        .padding(2)
        .background(
            Capsule().fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .help("Row density: Simple shows just the essentials, Advanced shows the command, chips, and process tree.")
    }

    private func segment(_ title: String, icon: String, value: PortManager.ViewDensity) -> some View {
        let selected = density == value
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85)) {
                density = value
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
            }
            .foregroundColor(selected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                ZStack {
                    if selected {
                        Capsule()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                            .matchedGeometryEffect(id: "slider", in: slider)
                    }
                }
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) view")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
