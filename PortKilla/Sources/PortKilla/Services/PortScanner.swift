import Foundation

// MARK: - PortScanner
class PortScanner {

    enum ScanError: Error {
        case invalidOutput
        case commandFailed(Int32)
    }

    /// pid -> working directory, cached because PIDs are stable across refreshes.
    private var cwdCache: [Int: String] = [:]

    /// Scans listening TCP ports and bound UDP sockets. `processes` supplies
    /// per-PID command, memory, and children so we don't shell out per port.
    func scanActivePorts(processes: ProcessTable) throws -> [PortInfo] {
        // Fast path: raw libproc syscalls, no subprocesses at all. nil means
        // libproc is unavailable; an empty list is a real answer and must not
        // fall through to lsof on every refresh of a quiet machine.
        if let native = NativeScanner.allListeners() {
            var raws: [RawListener] = []
            for listener in native {
                let raw = RawListener(
                    processName: processes.name(for: listener.pid) ?? "unknown",
                    pid: listener.pid,
                    user: NativeScanner.bsdInfo(Int32(listener.pid)).map { NativeScanner.username($0.pbi_uid) } ?? "?",
                    host: listener.host,
                    port: listener.port,
                    proto: listener.proto
                )
                mergeListener(raw, into: &raws)
            }
            return buildPortInfos(raws, processes: processes)
        }

        // Fallback: the lsof pipeline
        return try scanWithLsof(processes: processes)
    }

    private func scanWithLsof(processes: ProcessTable) throws -> [PortInfo] {
        // -iTCP -sTCP:LISTEN: listening TCP sockets only; -n/-P: skip name lookups.
        // lsof exits 1 when nothing matches, so that's an empty list, not an error.
        let tcpOutput: String
        do {
            tcpOutput = try CommandRunner.run(
                "/usr/sbin/lsof",
                ["-iTCP", "-sTCP:LISTEN", "-n", "-P"],
                timeout: 5.0,
                allowedExitCodes: [0, 1]
            )
        } catch let error as CommandRunner.CommandError {
            if case .failed(_, let code) = error { throw ScanError.commandFailed(code) }
            throw ScanError.invalidOutput
        }

        // UDP has no LISTEN state; a UDP scan failure shouldn't fail the refresh.
        let udpOutput = (try? CommandRunner.run(
            "/usr/sbin/lsof", ["-iUDP", "-n", "-P"], timeout: 5.0, allowedExitCodes: [0, 1]
        )) ?? ""

        let tcp = parsePortOutput(tcpOutput, processes: processes, proto: "tcp")
        let udp = parsePortOutput(udpOutput, processes: processes, proto: "udp")
        return (tcp + udp).sorted { $0.port < $1.port }
    }

    private struct RawListener {
        let processName: String
        let pid: Int
        let user: String
        var host: String
        let port: Int
        var proto: String = "tcp"

        var isExposedHost: Bool {
            PortInfo.isWildcardHost(host)
        }
    }

    /// IPv4/IPv6 duplicates of the same (pid, port, proto) merge into one row;
    /// when one of them binds all interfaces, the merged row keeps that host
    /// so the "exposed" badge can't be masked.
    private func mergeListener(_ raw: RawListener, into listeners: inout [RawListener]) {
        if let existing = listeners.firstIndex(where: {
            $0.port == raw.port && $0.pid == raw.pid && $0.proto == raw.proto
        }) {
            if raw.isExposedHost && !listeners[existing].isExposedHost {
                listeners[existing].host = raw.host
            }
            return
        }
        listeners.append(raw)
    }

    /// Parses lsof output into PortInfo objects
    func parsePortOutput(_ output: String, processes: ProcessTable, proto: String = "tcp") -> [PortInfo] {
        let lines = output.components(separatedBy: "\n")

        // Format of lsof output:
        // COMMAND   PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        // node    12345 user   23u  IPv4 0x...      0t0  TCP *:3000 (LISTEN)

        // Pass 1: collect raw listeners, merging IPv4/IPv6 duplicates of the
        // same (pid, port). When one duplicate binds all interfaces, the merged
        // row keeps that host so the "exposed" badge can't be masked.
        var listeners: [RawListener] = []

        for line in lines.dropFirst() { // Skip header
            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count >= 9 else { continue }

            let processName = String(components[0])
            guard let pid = Int(components[1]) else { continue }
            let user = String(components[2])

            guard let endpoint = extractEndpoint(from: components) else { continue }

            // UDP: ephemeral high ports are outgoing sockets (QUIC etc.),
            // not servers anyone would look for.
            if proto == "udp" && endpoint.port >= 49152 {
                continue
            }

            let raw = RawListener(
                processName: processName, pid: pid, user: user,
                host: endpoint.host, port: endpoint.port, proto: proto
            )
            mergeListener(raw, into: &listeners)
        }

        return buildPortInfos(listeners, processes: processes)
    }

    /// Enriches raw listeners with process details from the shared snapshot.
    private func buildPortInfos(_ listeners: [RawListener], processes: ProcessTable) -> [PortInfo] {
        refreshWorkingDirectories(for: listeners.map { $0.pid })

        let ports = listeners.map { raw -> PortInfo in
            let command = processes.command(for: raw.pid) ?? ""
            let processName = Self.bestProcessName(lsofName: raw.processName, entryName: processes.name(for: raw.pid))
            let memoryKb = processes.rssKB(for: raw.pid) ?? 0
            let memory = memoryKb > 0 ? MemoryFormat.string(kilobytes: memoryKb) : "N/A"
            let children = processes.children(of: raw.pid).map {
                PortInfo.ProcessInfo(pid: $0.pid, name: $0.name, command: $0.command)
            }
            let projectPath = projectWorthyPath(cwdCache[raw.pid])

            return PortInfo(
                port: raw.port,
                pid: raw.pid,
                processName: processName,
                command: command,
                user: raw.user,
                memoryUsage: memory,
                memorySizeKB: memoryKb,
                type: determinePortType(processName: processName, command: command),
                projectName: projectPath.map { ($0 as NSString).lastPathComponent } ?? extractProjectName(command: command),
                projectPath: projectPath,
                containerName: DockerService.shared.getContainerName(forPort: raw.port),
                children: children.isEmpty ? nil : children,
                bindAddress: raw.host,
                proto: raw.proto,
                cpuPercent: processes.cpuPercent(for: raw.pid) ?? 0,
                age: processes.ageSeconds(for: raw.pid).flatMap { ElapsedFormat.humanize(seconds: $0) },
                agentOwner: AgentAttribution.owner(ofPid: raw.pid, in: processes)
            )
        }

        return ports.sorted { $0.port < $1.port }
    }

    // MARK: - Working directories

    /// Resolves working directories for PIDs not yet cached — native syscall
    /// first, one lsof batch as fallback — and drops entries for dead PIDs.
    private func refreshWorkingDirectories(for pids: [Int]) {
        let live = Set(pids)
        cwdCache = cwdCache.filter { live.contains($0.key) }

        var missing = pids.filter { cwdCache[$0] == nil }
        guard !missing.isEmpty else { return }

        for pid in missing {
            if let path = NativeScanner.workingDirectory(Int32(pid)) {
                cwdCache[pid] = path
            }
        }
        missing = missing.filter { cwdCache[$0] == nil }

        if !missing.isEmpty {
            let pidList = missing.map(String.init).joined(separator: ",")
            // -Fn machine format: "p<pid>" line, then "n<path>" line per file
            let output = (try? CommandRunner.run(
                "/usr/sbin/lsof", ["-a", "-p", pidList, "-d", "cwd", "-Fn"],
                timeout: 3.0, allowedExitCodes: [0, 1]
            )) ?? ""

            for (pid, path) in Self.parseCwdOutput(output) {
                cwdCache[pid] = path
            }
        }

        // Negative-cache misses so we don't re-query them every refresh
        for pid in pids where cwdCache[pid] == nil {
            cwdCache[pid] = ""
        }
    }

    static func parseCwdOutput(_ output: String) -> [Int: String] {
        var result: [Int: String] = [:]
        var currentPid: Int?

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("p") {
                currentPid = Int(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = currentPid {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }

    /// A cwd only counts as a "project" when it's a real directory the user
    /// would recognize — not /, not the bare home folder.
    private func projectWorthyPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        if path == "/" || path == NSHomeDirectory() {
            return nil
        }
        return path
    }

    private func extractEndpoint(from lsofLineComponents: [Substring]) -> (host: String, port: Int)? {
        for token in lsofLineComponents.reversed() {
            // Connected sockets ("1.2.3.4:5->6.7.8.9:443") aren't listeners
            guard !token.contains("->") else { continue }
            guard token.contains(":"), let lastColon = token.lastIndex(of: ":") else { continue }

            let digits = token[token.index(after: lastColon)...]
                .trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
            guard let port = Int(digits) else { continue }

            // "[::1]:8080" -> "::1", "*:3000" -> "*", "127.0.0.1:3000" -> "127.0.0.1"
            let host = String(token[..<lastColon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            return (host, port)
        }
        return nil
    }

    private static let ideTools = [
        "antigravi", // Google's internal tool
        "cursor",
        "trae",
        "code helper", // VS Code
        "xcode",
        "electron",
        "google chrome",
        "slack",
        "intellij",
        "idea",
        "pycharm",
        "webstorm",
        "phpstorm",
        "goland",
        "rider",
        "rubymine",
        "datagrip",
        "appcode",
        "clion",
        "android studio",
        "sublime text",
        "atom",
        "nova",
        "bbedit",
        "coteditor",
        "textmate",
        "zed",
        "fleet",
        "windsurf"
    ]

    /// Determines port type based on process information.
    ///
    /// Matching is done on the executable's base name (exact) rather than
    /// substrings of the whole command: substring "go" used to classify
    /// "Google Chrome" as a Go server, which then fed the bulk-kill filters.
    func determinePortType(processName: String, command: String) -> PortInfo.PortType {
        let lowerProcess = processName.lowercased()
        let lowerCommand = command.lowercased()
        let executable = executableName(processName: processName, command: command)

        // IDEs and desktop apps first — their names would otherwise
        // substring-match runtime keywords below.
        if Self.ideTools.contains(where: { lowerProcess.contains($0) }) {
            return .ide
        }

        let nodeExecutables: Set = ["node", "npm", "npx", "yarn", "pnpm", "next", "vite", "webpack", "bun", "deno"]
        if nodeExecutables.contains(executable) {
            return .nodejs
        }

        // docker-proxy intentionally excluded: it fronts Docker-published ports
        // and is classified below as .docker (with the container name attached).
        let databases = ["postgres", "mysqld", "mysql", "mongod", "redis-server", "mariadbd", "mariadb"]
        if databases.contains(where: { executable == $0 || lowerProcess.contains($0) }) {
            return .database
        }

        let webServers = ["apache", "nginx", "httpd", "caddy"]
        if webServers.contains(where: { lowerProcess.contains($0) }) {
            return .webserver
        }

        if executable.hasPrefix("python") || executable == "gunicorn" || executable == "uvicorn" {
            return .python
        }

        if executable == "java" || lowerCommand.contains("gradle") {
            return .java
        }

        if executable == "ruby" || lowerCommand.contains("rails") {
            return .ruby
        }

        if executable.hasPrefix("php") {
            return .php
        }

        if executable == "go" || lowerCommand.hasPrefix("go run ") {
            return .go
        }

        if lowerProcess.contains("docker") || lowerProcess.contains("com.docker") {
            return .docker
        }

        return .other
    }

    /// lsof truncates COMMAND to ~9 chars ("com.docke"). When the ps snapshot
    /// has the full executable name and it extends the truncated one, use it.
    static func bestProcessName(lsofName: String, entryName: String?) -> String {
        guard let entryName, entryName.count > lsofName.count else { return lsofName }
        return entryName.lowercased().hasPrefix(lsofName.lowercased()) ? entryName : lsofName
    }

    private func executableName(processName: String, command: String) -> String {
        let firstToken = command.split(separator: " ").first.map(String.init) ?? ""
        let base = firstToken.split(separator: "/").last.map(String.init) ?? ""
        return (base.isEmpty ? processName : base).lowercased()
    }

    /// One-off child lookup (used by tests and ad-hoc callers).
    /// Bulk work should use a shared ProcessTable instead.
    func getChildProcesses(pid: Int) -> [PortInfo.ProcessInfo] {
        ProcessTable.capture().children(of: pid).map {
            PortInfo.ProcessInfo(pid: $0.pid, name: $0.name, command: $0.command)
        }
    }

    /// Extracts project name from command (if running from a project directory)
    private func extractProjectName(command: String) -> String? {
        let components = command.components(separatedBy: "/")
        for (index, component) in components.enumerated() {
            if ["projects", "workspace", "dev", "code"].contains(component.lowercased()) {
                if index + 1 < components.count {
                    return components[index + 1]
                }
            }
        }
        return nil
    }
}
