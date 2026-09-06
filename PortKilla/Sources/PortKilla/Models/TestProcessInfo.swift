import Foundation
import AppKit

struct TestProcessInfo: Identifiable, Codable, Equatable {
    var id: String {
        return "\(pid)-\(processName)"
    }
    let pid: Int
    let processName: String
    let command: String
    let memoryUsage: String
    let memorySizeKB: Int
    let cpuPercent: Double
    let type: TestType
    let agentOwner: AgentOwner?

    init(pid: Int, processName: String, command: String, memoryUsage: String, memorySizeKB: Int, cpuPercent: Double = 0, type: TestType, agentOwner: AgentOwner? = nil) {
        self.pid = pid
        self.processName = processName
        self.command = command
        self.memoryUsage = memoryUsage
        self.memorySizeKB = memorySizeKB
        self.cpuPercent = cpuPercent
        self.type = type
        self.agentOwner = agentOwner
    }

    func withOwner(_ owner: AgentOwner?) -> TestProcessInfo {
        TestProcessInfo(pid: pid, processName: processName, command: command, memoryUsage: memoryUsage,
                        memorySizeKB: memorySizeKB, cpuPercent: cpuPercent, type: type, agentOwner: owner)
    }

    // Only the runners ProcessScanner actually detects are represented here.
    // (Go/Cargo/Swift/PyTest detection isn't implemented; add a case here when
    // it is, so the enum never advertises capabilities that don't exist.)
    enum TestType: String, Codable {
        case jest = "Jest"
        case vitest = "Vitest"
        case mocha = "Mocha"
        case other = "Other Test"

        var icon: String {
            switch self {
            case .jest: return "flask.fill"
            case .vitest: return "bolt.shield.fill"
            case .mocha: return "cup.and.saucer.fill"
            case .other: return "testtube.2"
            }
        }

        var color: NSColor {
            switch self {
            case .jest: return .systemRed
            case .vitest: return .systemYellow
            case .mocha: return .systemBrown
            case .other: return .systemGray
            }
        }
    }
}
