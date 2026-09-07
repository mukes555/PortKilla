import AppKit
import PortNannyCore

// Colour is presentation, so it lives with the views; the core models stay
// Foundation-only.
extension PortInfo.PortType {
    var color: NSColor {
        switch self {
        case .nodejs: return .systemGreen
        case .database: return .systemYellow
        case .webserver: return .systemBlue
        case .python: return .systemBlue
        case .java: return .systemOrange
        case .ruby: return .systemRed
        case .php: return .systemPurple
        case .go: return .systemCyan
        case .docker: return .systemBlue
        case .ide: return .systemPurple
        case .other: return .systemGray
        }
    }
}

extension PortInfo.PortCategory {
    var color: NSColor {
        switch self {
        case .web: return .systemGreen
        case .database: return .systemYellow
        case .ide: return .systemPurple
        case .other: return .systemGray
        }
    }
}

extension TestProcessInfo.TestType {
    var color: NSColor {
        switch self {
        case .jest: return .systemRed
        case .vitest: return .systemYellow
        case .mocha: return .systemBrown
        case .other: return .systemGray
        }
    }
}
