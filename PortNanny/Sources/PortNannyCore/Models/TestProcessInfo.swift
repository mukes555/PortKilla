import Foundation

public struct TestProcessInfo: Identifiable, Codable, Equatable {
    public var id: String {
        return "\(pid)-\(processName)"
    }
    public let pid: Int
    public let processName: String
    public let command: String
    public let memoryUsage: String
    public let memorySizeKB: Int
    public let cpuPercent: Double
    public let type: TestType
    public let agentOwner: AgentOwner?

    public init(pid: Int, processName: String, command: String, memoryUsage: String, memorySizeKB: Int, cpuPercent: Double = 0, type: TestType, agentOwner: AgentOwner? = nil) {
        self.pid = pid
        self.processName = processName
        self.command = command
        self.memoryUsage = memoryUsage
        self.memorySizeKB = memorySizeKB
        self.cpuPercent = cpuPercent
        self.type = type
        self.agentOwner = agentOwner
    }

    public func withOwner(_ owner: AgentOwner?) -> TestProcessInfo {
        TestProcessInfo(pid: pid, processName: processName, command: command, memoryUsage: memoryUsage,
                        memorySizeKB: memorySizeKB, cpuPercent: cpuPercent, type: type, agentOwner: owner)
    }

    // Only the runners ProcessScanner actually detects are represented here.
    // (Go/Cargo/Swift/PyTest detection isn't implemented; add a case here when
    // it is, so the enum never advertises capabilities that don't exist.)
    public enum TestType: String, Codable {
        case jest = "Jest"
        case vitest = "Vitest"
        case mocha = "Mocha"
        case other = "Other Test"

        public var icon: String {
            switch self {
            case .jest: return "flask.fill"
            case .vitest: return "bolt.shield.fill"
            case .mocha: return "cup.and.saucer.fill"
            case .other: return "testtube.2"
            }
        }


    }
}
