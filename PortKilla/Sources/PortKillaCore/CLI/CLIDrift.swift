import Foundation

/// `portkilla drift`: servers that run somewhere other than where their
/// project's files say, and who holds the port they wanted.
public enum CLIDrift {

    public struct Report: Encodable {
        let schema = 1
        let drifted: [Drifted]
        let exitCode: Int32
    }

    public struct Drifted: Encodable {
        let port: Int
        let pid: Int
        let processName: String
        let projectName: String?
        let projectPath: String?
        let expected: ExpectedPort
        let heldBy: Holder?

        public struct Holder: Encodable {
            let pid: Int
            let processName: String
            let agentOwner: AgentOwner?
        }
    }

    public static func run(json: Bool) -> Int32 {
        let report = perform()
        if json {
            return PortKillaCLI.printJSON(report) ? report.exitCode : CLIExit.internalError
        }
        if report.drifted.isEmpty {
            print("Every server with a configured port is on it.")
            return CLIExit.ok
        }
        for item in report.drifted {
            print(describe(item))
        }
        return CLIExit.ok
    }

    public static func perform() -> Report {
        let scan = PortKillaCLI.scan(refreshDocker: false)
        let drifted = scan.ports.compactMap { port -> Drifted? in
            guard let expected = port.expectedPort else { return nil }
            let holder = scan.ports.first { $0.port == expected.port }.map {
                Drifted.Holder(pid: $0.pid, processName: $0.processName, agentOwner: $0.agentOwner)
            }
            return Drifted(port: port.port, pid: port.pid, processName: port.processName, projectName: port.projectName,
                           projectPath: port.projectPath, expected: expected, heldBy: holder)
        }
        return Report(drifted: drifted, exitCode: CLIExit.ok)
    }

    /// "node (PID 812) in shop runs on :3001; .env PORT says :3000, held by node (PID 700, Cursor)"
    public static func describe(_ item: Drifted) -> String {
        let project = item.projectName.map { " in \($0)" } ?? ""
        var line = "\(item.processName) (PID \(item.pid))\(project) runs on :\(item.port); \(item.expected.source) says :\(item.expected.port)"
        if let holder = item.heldBy {
            let owner = holder.agentOwner.map { ", \($0.label)" } ?? ""
            line += ", held by \(holder.processName) (PID \(holder.pid)\(owner))"
        } else {
            line += ", which is free now"
        }
        return line + "."
    }
}
