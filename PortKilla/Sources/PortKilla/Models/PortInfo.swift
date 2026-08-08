import Foundation
import AppKit

// MARK: - PortInfo Model
struct PortInfo: Identifiable, Codable, Equatable {
    var id: String {
        return "\(port)-\(pid)-\(proto)"
    }
    let port: Int
    let pid: Int
    let processName: String
    let command: String
    let user: String
    let memoryUsage: String
    let memorySizeKB: Int
    let type: PortType
    let projectName: String?
    /// Working directory of the process (used for "open in Finder/Terminal")
    let projectPath: String?
    let containerName: String?
    let children: [ProcessInfo]?
    /// Host the socket is bound to ("127.0.0.1", "*", "::1", …)
    let bindAddress: String?
    /// "tcp" or "udp"
    let proto: String
    let cpuPercent: Double
    /// Human-readable process age, e.g. "3h 12m"
    let age: String?

    /// A host bound to all interfaces (reachable from the local network, not
    /// just this machine). One source of truth for the "exposed" check —
    /// the scanner's raw-listener path uses this too.
    static func isWildcardHost(_ host: String) -> Bool {
        host == "*" || host == "0.0.0.0" || host == "::"
    }

    /// True when the socket listens on all interfaces.
    var isExposed: Bool {
        guard let bindAddress else { return false }
        return Self.isWildcardHost(bindAddress)
    }

    init(port: Int, pid: Int, processName: String, command: String, user: String, memoryUsage: String, memorySizeKB: Int, type: PortType, projectName: String? = nil, projectPath: String? = nil, containerName: String? = nil, children: [ProcessInfo]? = nil, bindAddress: String? = nil, proto: String = "tcp", cpuPercent: Double = 0, age: String? = nil) {
        self.port = port
        self.pid = pid
        self.processName = processName
        self.command = command
        self.user = user
        self.memoryUsage = memoryUsage
        self.memorySizeKB = memorySizeKB
        self.type = type
        self.projectName = projectName
        self.projectPath = projectPath
        self.containerName = containerName
        self.children = children
        self.bindAddress = bindAddress
        self.proto = proto
        self.cpuPercent = cpuPercent
        self.age = age
    }

    struct ProcessInfo: Identifiable, Codable, Equatable {
        var id: Int { pid }
        let pid: Int
        let name: String
        let command: String
    }

    enum PortCategory: String, Codable, CaseIterable {
        case web = "Web"
        case database = "Database"
        case ide = "IDE & Tools"
        case other = "Other"
    }

    enum PortType: String, Codable {
        case nodejs = "Node.js"
        case database = "Database"
        case webserver = "Web Server"
        case python = "Python"
        case java = "Java"
        case ruby = "Ruby"
        case php = "PHP"
        case go = "Go"
        case docker = "Docker"
        case ide = "IDE / Tool"
        case other = "Other"

        var category: PortCategory {
            switch self {
            case .nodejs, .webserver, .python, .java, .ruby, .php, .go:
                return .web
            case .database:
                return .database
            case .ide:
                return .ide
            case .docker, .other:
                return .other
            }
        }

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

        var icon: String {
            switch self {
            case .nodejs: return "hexagon.fill"
            case .database: return "cylinder.split.1x2.fill"
            case .webserver: return "globe"
            case .python: return "ladybug.fill" // Or custom
            case .java: return "cup.and.saucer.fill"
            case .ruby: return "diamond.fill"
            case .php: return "p.circle.fill"
            case .go: return "g.circle.fill"
            case .docker: return "shippingbox.fill"
            case .ide: return "hammer.fill"
            case .other: return "gearshape.fill"
            }
        }
    }
}
