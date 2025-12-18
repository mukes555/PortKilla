import Foundation
import AppKit

struct TestProcessInfo: Identifiable, Codable {
    var id: String {
        return "\(pid)-\(processName)"
    }
    let pid: Int
    let processName: String
    let command: String
    let memoryUsage: String
    let memorySizeKB: Int
    let type: TestType

    init(pid: Int, processName: String, command: String, memoryUsage: String, memorySizeKB: Int, type: TestType) {
        self.pid = pid
        self.processName = processName
        self.command = command
        self.memoryUsage = memoryUsage
        self.memorySizeKB = memorySizeKB
        self.type = type
    }

    enum TestType: String, Codable {
        case jest = "Jest"
        case vitest = "Vitest"
        case mocha = "Mocha"
        case golang = "Go Test"
        case cargo = "Cargo Test"
        case swift = "Swift Test"
        case python = "PyTest"
        case other = "Other Test"

        var icon: String {
            switch self {
            case .jest: return "flask.fill"
            case .vitest: return "bolt.shield.fill"
            case .mocha: return "cup.and.saucer.fill"
            case .golang: return "g.circle.fill"
            case .cargo: return "shippingbox.fill"
            case .swift: return "swift"
            case .python: return "ladybug.fill"
            case .other: return "testtube.2"
            }
        }

        var color: NSColor {
            switch self {
            case .jest: return .systemRed
            case .vitest: return .systemYellow
            case .mocha: return .systemBrown
            case .golang: return .systemCyan
            case .cargo: return .systemOrange
            case .swift: return .systemOrange
            case .python: return .systemBlue
            case .other: return .systemGray
            }
        }
    }
}
