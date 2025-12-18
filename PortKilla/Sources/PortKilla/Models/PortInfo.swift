import Foundation
import AppKit

// MARK: - PortInfo Model
struct PortInfo: Identifiable, Codable {
    let id: UUID
    let port: Int
    let pid: Int
    let processName: String
    let command: String
    let user: String
    let memoryUsage: String
    let type: PortType
    let projectName: String?

    init(port: Int, pid: Int, processName: String, command: String, user: String, memoryUsage: String, type: PortType, projectName: String? = nil) {
        self.id = UUID()
        self.port = port
        self.pid = pid
        self.processName = processName
        self.command = command
        self.user = user
        self.memoryUsage = memoryUsage
        self.type = type
        self.projectName = projectName
    }

    enum PortType: String, Codable {
        case nodejs = "Node.js"
        case database = "Database"
        case webserver = "Web Server"
        case other = "Other"

        var color: NSColor {
            switch self {
            case .nodejs: return .systemGreen
            case .database: return .systemYellow
            case .webserver: return .systemOrange
            case .other: return .systemGray
            }
        }

        var icon: String {
            switch self {
            case .nodejs: return "hexagon.fill"
            case .database: return "cylinder.split.1x2.fill"
            case .webserver: return "globe"
            case .other: return "gearshape.fill"
            }
        }
    }
}
