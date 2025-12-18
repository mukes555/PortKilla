import Foundation

// MARK: - PortScanner
class PortScanner {

    /// Scans for all active TCP ports and returns detailed information
    func scanActivePorts() -> [PortInfo] {
        let task = Process()
        let pipe = Pipe()

        // lsof -iTCP -sTCP:LISTEN -n -P
        // -iTCP: select IPv4/IPv6 files
        // -sTCP:LISTEN: only show listening ports
        // -n: no host names
        // -P: no port names
        task.launchPath = "/usr/sbin/lsof" // Usually in /usr/sbin/lsof on macOS
        task.arguments = ["-iTCP", "-sTCP:LISTEN", "-n", "-P"]
        task.standardOutput = pipe

        do {
            try task.run()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            return parsePortOutput(output)
        } catch {
            print("Error scanning ports: \(error)")
            // Fallback to /usr/bin/lsof if /usr/sbin/lsof fails or vice versa?
            // Actually lsof is usually in /usr/sbin.
            return []
        }
    }

    /// Parses lsof output into PortInfo objects
    private func parsePortOutput(_ output: String) -> [PortInfo] {
        let lines = output.components(separatedBy: "\n")
        var ports: [PortInfo] = []

        // Format of lsof output:
        // COMMAND   PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        // node    12345 user   23u  IPv4 0x...      0t0  TCP *:3000 (LISTEN)

        for line in lines.dropFirst() { // Skip header
            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count >= 9 else { continue }

            let processName = String(components[0])
            let pid = Int(components[1]) ?? 0
            let user = String(components[2])

            // Extract port from "localhost:3000" or "*:3000"
            // The address is usually the 9th component (index 8)
            let addressComponents = components[8].split(separator: ":")
            guard let portString = addressComponents.last,
                  let port = Int(portString) else { continue }

            // Filter out duplicate ports if multiple processes share it (rare but possible)
            // or if the same process listens on IPv4 and IPv6
            if ports.contains(where: { $0.port == port }) {
                continue
            }

            // Get process details
            let command = getProcessCommand(pid: pid)
            let (memory, memoryKb) = getProcessMemory(pid: pid)
            let type = determinePortType(processName: processName, command: command)
            let projectName = extractProjectName(command: command)

            let portInfo = PortInfo(
                port: port,
                pid: pid,
                processName: processName,
                command: command,
                user: user,
                memoryUsage: memory,
                memorySizeKB: memoryKb,
                type: type,
                projectName: projectName
            )

            ports.append(portInfo)
        }

        return ports.sorted { $0.port < $1.port }
    }

    /// Determines port type based on process information
    private func determinePortType(processName: String, command: String) -> PortInfo.PortType {
        let lowerProcess = processName.lowercased()
        let lowerCommand = command.lowercased()

        // Node.js & JS Ecosystem
        let nodeProcesses = ["node", "npm", "yarn", "pnpm", "next", "vite", "webpack", "bun", "deno"]
        if nodeProcesses.contains(where: { lowerProcess.contains($0) }) ||
           lowerCommand.contains("npm") || lowerCommand.contains("node") {
            return .nodejs
        }

        // Databases
        let databases = ["postgres", "mysql", "mongod", "redis-server", "mariadb", "mysqld", "docker-proxy"]
        if databases.contains(where: { lowerProcess.contains($0) }) {
            return .database
        }

        // Web Servers
        let webServers = ["apache", "nginx", "httpd", "caddy"]
        if webServers.contains(where: { lowerProcess.contains($0) }) {
            return .webserver
        }

        // Python
        if lowerProcess.contains("python") || lowerCommand.contains("python") || lowerCommand.contains("gunicorn") || lowerCommand.contains("uvicorn") {
            return .python
        }

        // Java
        if lowerProcess.contains("java") || lowerCommand.contains("java") || lowerCommand.contains("gradle") || lowerCommand.contains("mvn") {
            return .java
        }

        // Ruby
        if lowerProcess.contains("ruby") || lowerCommand.contains("rails") || lowerCommand.contains("bundle") {
            return .ruby
        }

        // PHP
        if lowerProcess.contains("php") || lowerCommand.contains("php") || lowerCommand.contains("laravel") {
            return .php
        }

        // Go
        if lowerProcess.contains("go") || lowerCommand.contains("go run") || lowerCommand.contains("air") {
            return .go
        }

        // Docker
        if lowerProcess.contains("docker") || lowerProcess.contains("com.docker") {
            return .docker
        }

        // IDEs & Tools
        let ideTools = [
            "antigravi", // Google's internal tool
            "cursor",
            "trae",
            "code helper", // VS Code
            "xcode",
            "electron",
            "google chrome",
            "slack",
            "intellij", // IntelliJ IDEA
            "idea",     // IntelliJ IDEA process name often 'idea'
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
            "zed",      // Zed Editor
            "fleet",    // Fleet Editor
            "windsurf"  // Windsurf
        ]
        if ideTools.contains(where: { lowerProcess.contains($0) }) {
            return .ide
        }

        return .other
    }

    /// Gets full command for a process
    private func getProcessCommand(pid: Int) -> String {
        let task = Process()
        let pipe = Pipe()

        task.launchPath = "/bin/ps"
        task.arguments = ["-p", "\(pid)", "-o", "command="]
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }

    /// Gets memory usage for a process
    private func getProcessMemory(pid: Int) -> (String, Int) {
        let task = Process()
        let pipe = Pipe()

        task.launchPath = "/bin/ps"
        task.arguments = ["-p", "\(pid)", "-o", "rss="]
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8),
               let kb = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return (formatMemory(kilobytes: kb), kb)
            }
        } catch {
            return ("N/A", 0)
        }

        return ("N/A", 0)
    }

    /// Formats memory size
    private func formatMemory(kilobytes: Int) -> String {
        let mb = Double(kilobytes) / 1024.0
        if mb < 1 {
            return "\(kilobytes)KB"
        } else if mb < 1024 {
            return String(format: "%.1fMB", mb)
        } else {
            return String(format: "%.2fGB", mb / 1024.0)
        }
    }

    /// Extracts project name from command (if running from a project directory)
    private func extractProjectName(command: String) -> String? {
        // Look for common patterns like "npm run dev" in "/Users/dev/projects/my-app"
        // This is tricky because `ps` command output might not show CWD.
        // `lsof -p PID -F n` might give open files including CWD but that's expensive.
        // We can try to guess from the command arguments if they contain paths.

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
