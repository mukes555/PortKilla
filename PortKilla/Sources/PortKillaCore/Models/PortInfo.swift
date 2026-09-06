import Foundation

// MARK: - PortInfo Model
public struct PortInfo: Identifiable, Codable, Equatable {
    public var id: String {
        return "\(port)-\(pid)-\(proto)"
    }
    public let port: Int
    public let pid: Int
    public let processName: String
    public let command: String
    public let user: String
    public let memoryUsage: String
    public let memorySizeKB: Int
    public let type: PortType
    public let projectName: String?
    /// Working directory of the process (used for "open in Finder/Terminal")
    public let projectPath: String?
    public let containerName: String?
    public let children: [ProcessInfo]?
    /// Host the socket is bound to ("127.0.0.1", "*", "::1", …)
    public let bindAddress: String?
    /// "tcp" or "udp"
    public let proto: String
    public let cpuPercent: Double
    /// Human-readable process age, e.g. "3h 12m"
    public let age: String?
    /// The AI coding agent that spawned this process, if it could be attributed.
    public let agentOwner: AgentOwner?
    /// Clients currently connected (established TCP connections on this
    /// port). Killing a server with clients is a different decision from
    /// killing an idle one.
    public let connections: Int
    /// A supervisor that would undo a plain kill (pm2, launchd, Docker, a
    /// reloader), with the verb that stops it for real.
    public let managedBy: ManagedRuntime?

    /// A host bound to all interfaces (reachable from the local network, not
    /// just this machine). One source of truth for the "exposed" check —
    /// the scanner's raw-listener path uses this too.
    public static func isWildcardHost(_ host: String) -> Bool {
        host == "*" || host == "0.0.0.0" || host == "::"
    }

    /// True when the socket listens on all interfaces.
    public var isExposed: Bool {
        guard let bindAddress else { return false }
        return Self.isWildcardHost(bindAddress)
    }

    public init(port: Int, pid: Int, processName: String, command: String, user: String, memoryUsage: String, memorySizeKB: Int, type: PortType, projectName: String? = nil, projectPath: String? = nil, containerName: String? = nil, children: [ProcessInfo]? = nil, bindAddress: String? = nil, proto: String = "tcp", cpuPercent: Double = 0, age: String? = nil, agentOwner: AgentOwner? = nil, connections: Int = 0, managedBy: ManagedRuntime? = nil) {
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
        self.agentOwner = agentOwner
        self.connections = connections
        self.managedBy = managedBy
    }

    public struct ProcessInfo: Identifiable, Codable, Equatable {
        public var id: Int { pid }
        public let pid: Int
        public let name: String
        public let command: String

        public init(pid: Int, name: String, command: String) {
            self.pid = pid
            self.name = name
            self.command = command
        }
    }

    public enum PortCategory: String, Codable, CaseIterable {
        case web = "Web"
        case database = "Database"
        case ide = "IDE & Tools"
        case other = "Other"
    }

    public enum PortType: String, Codable {
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

        public var category: PortCategory {
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



        public var icon: String {
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
